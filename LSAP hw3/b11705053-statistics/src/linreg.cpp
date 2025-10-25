\
#include "linreg.h"
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <cctype>
#include <limits>
#include <cstdio>

static std::vector<std::string> split(const std::string& s, char sep=',') {
    std::vector<std::string> out;
    std::string cur;
    for (char c : s) {
        if (c == sep) { out.push_back(cur); cur.clear(); }
        else { cur.push_back(c); }
    }
    out.push_back(cur);
    return out;
}

static std::string trim(const std::string& s) {
    size_t i=0, j=s.size();
    while (i<j && std::isspace((unsigned char)s[i])) ++i;
    while (j>i && std::isspace((unsigned char)s[j-1])) --j;
    return s.substr(i, j-i);
}

CSVData read_csv_numeric(const std::string& path, bool allow_empty) {
    std::ifstream fin(path);
    if (!fin) throw std::runtime_error("cannot open file: " + path);
    CSVData data;
    std::string line;
    size_t lineno = 0;
    while (std::getline(fin, line)) {
        ++lineno;
        if (!allow_empty && trim(line).empty()) continue; // skip blank lines
        auto toks = split(line, ',');
        std::vector<double> row;
        row.reserve(toks.size());
        for (size_t c=0;c<toks.size();++c) {
            std::string t = trim(toks[c]);
            if (t.empty()) {
                std::ostringstream oss;
                oss << "parse error: empty value at line " << lineno << ", col " << (c+1);
                throw std::runtime_error(oss.str());
            }
            try {
                size_t pos=0;
                double v = std::stod(t, &pos);
                if (pos != t.size()) {
                    std::ostringstream oss;
                    oss << "parse error: non-numeric token \"" << t << "\" at line " << lineno << ", col " << (c+1);
                    throw std::runtime_error(oss.str());
                }
                row.push_back(v);
            } catch (const std::exception&) {
                std::ostringstream oss;
                oss << "parse error: cannot convert \"" << t << "\" to number at line " << lineno << ", col " << (c+1);
                throw std::runtime_error(oss.str());
            }
        }
        if (!row.empty()) data.rows.push_back(std::move(row));
    }
    if (data.rows.empty()) {
        if (allow_empty) return data;
        throw std::runtime_error("no data rows found in: " + path);
    }
    return data;
}

// Solve A x = b via Gaussian elimination with partial pivoting
static std::vector<double> solve_linear(std::vector<std::vector<double>> A, std::vector<double> b) {
    const size_t n = A.size();
    if (n == 0) throw std::runtime_error("solve_linear: empty matrix");
    for (size_t i=0;i<n;++i) {
        if (A[i].size() != n) throw std::runtime_error("solve_linear: matrix not square");
    }
    if (b.size() != n) throw std::runtime_error("solve_linear: dimension mismatch");

    for (size_t i=0;i<n;++i) {
        // pivot
        size_t piv = i;
        double best = std::abs(A[i][i]);
        for (size_t r=i+1;r<n;++r) {
            double val = std::abs(A[r][i]);
            if (val > best) { best = val; piv = r; }
        }
        if (best < 1e-15) throw std::runtime_error("solve_linear: singular matrix (near-zero pivot)");
        if (piv != i) {
            std::swap(A[piv], A[i]);
            std::swap(b[piv], b[i]);
        }
        // eliminate
        for (size_t r=i+1;r<n;++r) {
            double f = A[r][i] / A[i][i];
            if (std::abs(f) < 1e-18) continue;
            for (size_t c=i;c<n;++c) A[r][c] -= f * A[i][c];
            b[r] -= f * b[i];
        }
    }
    // back-substitute
    std::vector<double> x(n, 0.0);
    for (int i=int(n)-1;i>=0;--i) {
        double sum = b[i];
        for (size_t c=i+1;c<n;++c) sum -= A[i][c]*x[c];
        x[i] = sum / A[i][i];
    }
    return x;
}

LinRegModel fit_ols(const std::vector<std::vector<double>>& X_no_intercept,
                    const std::vector<double>& y) {
    size_t n = X_no_intercept.size();
    if (n == 0) throw std::runtime_error("fit_ols: empty dataset");
    size_t p = X_no_intercept[0].size(); // number of features
    for (const auto& r : X_no_intercept) {
        if (r.size() != p) throw std::runtime_error("fit_ols: inconsistent feature dimension");
    }
    if (y.size() != n) throw std::runtime_error("fit_ols: y dimension mismatch");

    // Build X with intercept: n x (p+1)
    size_t d = p + 1;
    // Compute XtX and XtY
    std::vector<std::vector<double>> XtX(d, std::vector<double>(d, 0.0));
    std::vector<double> XtY(d, 0.0);

    for (size_t i=0;i<n;++i) {
        // row vector [1, x1, x2, ... xp]
        std::vector<double> xi(d, 1.0);
        for (size_t j=0;j<p;++j) xi[j+1] = X_no_intercept[i][j];

        for (size_t a=0;a<d;++a) {
            XtY[a] += xi[a] * y[i];
            for (size_t b=0;b<d;++b) {
                XtX[a][b] += xi[a] * xi[b];
            }
        }
    }

    auto beta = solve_linear(XtX, XtY);
    LinRegModel m; m.beta = std::move(beta);
    return m;
}

std::vector<double> predict(const LinRegModel& model,
                            const std::vector<std::vector<double>>& X_no_intercept) {
    size_t n = X_no_intercept.size();
    size_t p = model.beta.size();
    if (p == 0) throw std::runtime_error("predict: empty model");
    if (p < 1) throw std::runtime_error("predict: bad model size");
    size_t feat = p - 1;
    std::vector<double> yhat(n, 0.0);
    for (size_t i=0;i<n;++i) {
        if (X_no_intercept[i].size() != feat)
            throw std::runtime_error("predict: feature dimension mismatch at row " + std::to_string(i+1));
        double v = model.beta[0];
        for (size_t j=0;j<feat;++j) v += model.beta[j+1] * X_no_intercept[i][j];
        yhat[i] = v;
    }
    return yhat;
}

void save_model_json(const LinRegModel& model, const std::string& path) {
    std::ofstream fout(path);
    if (!fout) throw std::runtime_error("cannot open for write: " + path);
    fout << "{\n  \"beta\": [";
    for (size_t i=0;i<model.beta.size();++i) {
        if (i) fout << ", ";
        // Write with sufficient precision
        fout.setf(std::ios::fixed); fout.precision(10);
        fout << model.beta[i];
    }
    fout << "]\n}\n";
}

LinRegModel load_model_json(const std::string& path) {
    std::ifstream fin(path);
    if (!fin) throw std::runtime_error("cannot open model: " + path);
    std::string s((std::istreambuf_iterator<char>(fin)), std::istreambuf_iterator<char>());
    // very small hand-rolled parser for: {"beta":[a,b,c]}
    auto pos = s.find("[");
    auto pos2 = s.find("]", pos == std::string::npos ? 0 : pos);
    if (pos == std::string::npos || pos2 == std::string::npos || pos2 <= pos)
        throw std::runtime_error("bad model json: missing beta array");
    std::string arr = s.substr(pos+1, pos2-pos-1);
    std::vector<double> beta;
    std::stringstream ss(arr);
    std::string tok;
    while (std::getline(ss, tok, ',')) {
        std::string t = trim(tok);
        if (t.empty()) continue;
        try {
            size_t p=0; double v = std::stod(t, &p);
            beta.push_back(v);
        } catch (...) {
            throw std::runtime_error("bad model json: non-number token in beta array");
        }
    }
    if (beta.empty()) throw std::runtime_error("bad model json: empty beta");
    LinRegModel m; m.beta = std::move(beta);
    return m;
}
