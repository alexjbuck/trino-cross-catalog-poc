-- Create schema in iceberg catalog
CREATE SCHEMA IF NOT EXISTS iceberg.demo;

-- Create the data table
CREATE TABLE iceberg.demo.data (
    date DATE,
    data INTEGER
);

-- Insert test data for each day
INSERT INTO iceberg.demo.data VALUES
    (DATE '2024-01-01', 100),
    (DATE '2024-01-02', 200),
    (DATE '2024-01-03', 300),
    (DATE '2024-01-04', 400),
    (DATE '2024-01-05', 500),
    (DATE '2024-01-06', 600),
    (DATE '2024-01-07', 700);
