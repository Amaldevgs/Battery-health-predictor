-- ============================================
-- Battery Health Predictor — queries.sql
-- Author: Amal Dev
-- Dataset: NASA Battery Cycle Dataset
-- Description: SQL queries for battery health
--              analysis and prediction pipeline
-- ============================================

USE battery_health;

-- ============================================
-- STEP 1: DATABASE SETUP
-- ============================================

CREATE DATABASE IF NOT EXISTS battery_health;

CREATE TABLE IF NOT EXISTS battery_cycles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    battery_id VARCHAR(10),
    cycle INT,
    voltage FLOAT,
    temperature FLOAT,
    capacity FLOAT,
    soh FLOAT,
    rul INT
);

-- ============================================
-- STEP 2: DATA QUALITY CHECKS
-- ============================================

-- Total record count
SELECT COUNT(*) AS total_records 
FROM battery_cycles;

-- Records per battery
SELECT battery_id, 
       COUNT(*) AS total_cycles
FROM battery_cycles
GROUP BY battery_id
ORDER BY total_cycles DESC;

-- Null value check across all columns
SELECT 
    SUM(CASE WHEN battery_id IS NULL THEN 1 ELSE 0 END) AS null_battery_id,
    SUM(CASE WHEN cycle IS NULL THEN 1 ELSE 0 END) AS null_cycle,
    SUM(CASE WHEN voltage IS NULL THEN 1 ELSE 0 END) AS null_voltage,
    SUM(CASE WHEN temperature IS NULL THEN 1 ELSE 0 END) AS null_temperature,
    SUM(CASE WHEN capacity IS NULL THEN 1 ELSE 0 END) AS null_capacity,
    SUM(CASE WHEN soh IS NULL THEN 1 ELSE 0 END) AS null_soh,
    SUM(CASE WHEN rul IS NULL THEN 1 ELSE 0 END) AS null_rul
FROM battery_cycles;

-- Basic statistics
SELECT 
    MIN(soh) AS min_soh,
    MAX(soh) AS max_soh,
    AVG(soh) AS avg_soh,
    MIN(rul) AS min_rul,
    MAX(rul) AS max_rul,
    AVG(rul) AS avg_rul,
    MIN(temperature) AS min_temp,
    MAX(temperature) AS max_temp
FROM battery_cycles;

-- ============================================
-- STEP 3: HEALTH STATUS VIEW
-- ============================================

-- Create enriched view with health classification
CREATE OR REPLACE VIEW battery_health_status AS
SELECT 
    id,
    battery_id,
    cycle,
    voltage,
    temperature,
    capacity,
    soh,
    rul,
    CASE 
        WHEN soh < 0.8 THEN 'Critical'
        WHEN soh < 0.9 THEN 'Warning'
        ELSE 'Healthy'
    END AS health_label,
    ROUND((1 - soh) * 100, 2) AS degradation_pct
FROM battery_cycles;

-- Verify VIEW works
SELECT * FROM battery_health_status LIMIT 10;

-- Health distribution across all batteries
SELECT 
    health_label,
    COUNT(*) AS total_records,
    ROUND(AVG(soh), 4) AS avg_soh,
    ROUND(AVG(rul), 2) AS avg_rul
FROM battery_health_status
GROUP BY health_label
ORDER BY avg_soh DESC;

-- ============================================
-- STEP 4: ANALYTICAL QUERIES
-- ============================================

-- Q1: Most degraded batteries
SELECT 
    battery_id,
    ROUND(AVG(soh), 4) AS avg_soh,
    ROUND(AVG(degradation_pct), 2) AS avg_degradation,
    MIN(rul) AS min_rul,
    COUNT(*) AS total_cycles
FROM battery_health_status
GROUP BY battery_id
ORDER BY avg_soh ASC
LIMIT 10;

-- Q2: Temperature effect on capacity
SELECT 
    ROUND(temperature, 0) AS temp_rounded,
    COUNT(*) AS records,
    ROUND(AVG(capacity), 4) AS avg_capacity,
    ROUND(AVG(soh), 4) AS avg_soh
FROM battery_cycles
GROUP BY ROUND(temperature, 0)
ORDER BY temp_rounded ASC;

-- Q3: Batteries needing replacement (RUL less than 10)
SELECT 
    battery_id,
    MIN(rul) AS min_rul,
    ROUND(AVG(soh), 4) AS avg_soh,
    health_label
FROM battery_health_status
GROUP BY battery_id, health_label
HAVING MIN(rul) < 10
ORDER BY min_rul ASC;

-- Q4: SOH drop per cycle using window function
SELECT 
    battery_id,
    cycle,
    soh,
    LAG(soh) OVER (
        PARTITION BY battery_id 
        ORDER BY cycle
    ) AS prev_soh,
    ROUND(soh - LAG(soh) OVER (
        PARTITION BY battery_id 
        ORDER BY cycle
    ), 6) AS soh_change
FROM battery_cycles
ORDER BY battery_id, cycle
LIMIT 20;

-- ============================================
-- STEP 5: STORED PROCEDURE FOR BATTERY ALERTS
-- ============================================

DELIMITER //

CREATE PROCEDURE get_critical_batteries()
BEGIN
    SELECT 
        battery_id,
        ROUND(AVG(soh), 4) AS avg_soh,
        MIN(rul) AS min_rul,
        MAX(cycle) AS total_cycles,
        ROUND(AVG(degradation_pct), 2) AS avg_degradation,
        health_label
    FROM battery_health_status
    GROUP BY battery_id, health_label
    HAVING AVG(soh) < 0.75
    ORDER BY min_rul ASC;
END //

DELIMITER ;

-- Call the procedure
CALL get_critical_batteries();

-- ============================================
-- STEP 6: EXPORT CLEANED AND ENRICHED DATA
-- ============================================

SELECT 
    battery_id,
    cycle,
    voltage,
    temperature,
    capacity,
    soh,
    rul,
    health_label,
    degradation_pct
FROM battery_health_status
ORDER BY battery_id, cycle;
