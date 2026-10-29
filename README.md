# Azure Lakehouse: Governed Sales Star Schema with SCD2

[![CI](https://github.com/sushii-code/azure-lakehouse-sales/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/sushii-code/azure-lakehouse-sales/actions/workflows/ci.yml)

> Status: in progress

## Business problem
[2–3 sentences: orders, customers, payments and products sit in separate systems; teams don't trust revenue numbers; the company needs one governed, daily-refreshed source of truth.]

## Headline outcome
[Fill in with real numbers when finished: rows processed, dbt tests, incremental vs full-refresh time at 1% daily change, PII tokenised before Gold.]

## Architecture
![Architecture](docs/images/architecture.png)

Raw files → **Bronze** (Delta, schema checks, quarantine) → **Silver** (PySpark cleaning, PII tokenisation) → **Gold** (dbt star schema, SCD2) → business SQL

## Data
- Olist Brazilian E-Commerce dataset (Kaggle, 9 tables) for realistic business data
- A reproducible synthetic generator (`src/simulator/`) for daily change events and the 100k / 1M / 5M benchmark

## Data model
See [`docs/data_model.md`](docs/data_model.md).

## How to run
[Setup steps, one command to run the pipeline, and teardown.]

## Results
[Benchmark table, test results, screenshots.]

## Design decisions and trade-offs
[Why Databricks Free Edition for development and Terraform for Azure deployment; why event-aware SCD2; why tokenisation over hashing; what you rejected.]

## What I would change at scale
[...]

## Tech stack
Python, PySpark, SQL, Databricks, Delta Lake, dbt, Terraform, Azure Data Lake Storage, Azure Key Vault, GitHub Actions
