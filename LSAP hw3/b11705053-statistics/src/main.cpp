\
#include "linreg.h"
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <stdexcept>

static void print_help() {
    std::cout <<
R"(Usage:
  b11705053-statistics --fit <train.csv> --out <model.json>
    train.csv rows: y,x1,x2,...,xp  (headerless, numeric)

  b11705053-statistics --apply <model.json> --in <X.csv> --out <pred.txt>
    X.csv rows: x1,x2,...,xp (headerless, numeric)
    pred.txt: one prediction per line

  b11705053-statistics -h | --help
Notes:
  * CSV must be numeric. Whitespace allowed around commas.
  * Clear errors with line/column on parse failure.)" << std::endl;
}

struct Cmd {
    std::string mode; // "fit" or "apply"
    std::string train_csv;
    std::string model_json;
    std::string X_csv;
    std::string out_path;
};

static Cmd parse_args(int argc, char** argv) {
    Cmd c;
    if (argc == 1) { print_help(); std::exit(0); }
    for (int i=1;i<argc;i++) {
        std::string a = argv[i];
        if (a == "-h" || a == "--help") { print_help(); std::exit(0); }
        else if (a == "--fit" && i+1<argc) { c.mode = "fit"; c.train_csv = argv[++i]; }
        else if (a == "--apply" && i+1<argc) { c.mode = "apply"; c.model_json = argv[++i]; }
        else if (a == "--in" && i+1<argc) { c.X_csv = argv[++i]; }
        else if (a == "--out" && i+1<argc) { c.out_path = argv[++i]; }
        else if (a == "--model" && i+1<argc) { c.model_json = argv[++i]; } // alias if needed
        else {
            std::cerr << "Unknown or malformed arg: " << a << "\n";
            print_help();
            std::exit(2);
        }
    }
    if (c.mode == "fit") {
        if (c.train_csv.empty() || c.out_path.empty()) {
            std::cerr << "Missing --fit <train.csv> or --out <model.json>\n";
            std::exit(2);
        }
    } else if (c.mode == "apply") {
        if (c.model_json.empty() || c.X_csv.empty() || c.out_path.empty()) {
            std::cerr << "Missing --apply <model.json> or --in <X.csv> or --out <pred.txt>\n";
            std::exit(2);
        }
    } else {
        std::cerr << "You must specify --fit or --apply\n";
        print_help();
        std::exit(2);
    }
    return c;
}

int main(int argc, char** argv) {
    try {
        Cmd cmd = parse_args(argc, argv);
        if (cmd.mode == "fit") {
            CSVData df = read_csv_numeric(cmd.train_csv);
            // Expect at least 2 columns: y and one x
            size_t n = df.rows.size();
            if (n == 0) throw std::runtime_error("fit: empty dataset");
            size_t m = df.rows[0].size();
            if (m < 2) throw std::runtime_error("fit: need at least 2 columns: y and x1");
            std::vector<double> y; y.reserve(n);
            std::vector<std::vector<double>> X; X.reserve(n);
            for (size_t i=0;i<n;++i) {
                if (df.rows[i].size() != m)
                    throw std::runtime_error("fit: inconsistent column count at line " + std::to_string(i+1));
                y.push_back(df.rows[i][0]);
                std::vector<double> xi(df.rows[i].begin()+1, df.rows[i].end());
                X.push_back(std::move(xi));
            }
            LinRegModel model = fit_ols(X, y);
            save_model_json(model, cmd.out_path);
            std::cout << "Model saved to " << cmd.out_path << " with " << (model.beta.size()-1) << " features.\n";
        } else {
            // apply
            LinRegModel model = load_model_json(cmd.model_json);
            CSVData dfX = read_csv_numeric(cmd.X_csv);
            size_t feat = model.beta.size()-1;
            for (size_t i=0;i<dfX.rows.size();++i) {
                if (dfX.rows[i].size() != feat) {
                    throw std::runtime_error("apply: feature count mismatch at line " + std::to_string(i+1) +
                        " (expected " + std::to_string(feat) + " columns)");
                }
            }
            auto yhat = predict(model, dfX.rows);
            std::ofstream fout(cmd.out_path);
            if (!fout) throw std::runtime_error("cannot open for write: " + cmd.out_path);
            fout.setf(std::ios::fixed); fout.precision(10);
            for (double v : yhat) fout << v << "\n";
            std::cout << "Predictions written to " << cmd.out_path << " (" << yhat.size() << " lines)\n";
        }
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "error: " << e.what() << "\n";
        return 1;
    }
}
