# b11705053-statistics

A tiny C++ CLI to fit/apply multiple linear regression (no third-party libraries).

## Build

```bash
sudo apt update
sudo apt install -y build-essential cmake
mkdir -p build && cd build
cmake ..
cmake --build . -j
./b11705053-statistics -h
```

## Usage

Training CSV (headerless): each row = y,x1,x2,...,xp
```bash
./b11705053-statistics --fit ../data/train.csv --out model.json
```

Apply:
X.csv: each row = x1,x2,...,xp
```bash
./b11705053-statistics --apply model.json --in ../data/X.csv --out pred.txt
```

## Debian Packaging

From project root:
```bash
sudo apt install -y debhelper devscripts
debuild -us -uc
```

The `.deb` will be in the parent directory.
