\
#pragma once
#include <vector>
#include <string>

struct LinRegModel {
    std::vector<double> beta; // beta[0] = intercept, beta[1..p] = coefficients
};

struct CSVData {
    std::vector<std::vector<double>> rows;
};

CSVData read_csv_numeric(const std::string& path, bool allow_empty=false);

LinRegModel fit_ols(const std::vector<std::vector<double>>& X_no_intercept,
                    const std::vector<double>& y);

std::vector<double> predict(const LinRegModel& model,
                            const std::vector<std::vector<double>>& X_no_intercept);

void save_model_json(const LinRegModel& model, const std::string& path);
LinRegModel load_model_json(const std::string& path);
