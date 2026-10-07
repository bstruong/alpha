# Architecture Specification: Rate Limiter

## 1. Overview
The rate limiter must accurately calculate remaining request quotas across multiple tiers without losing precision.

## 2. Core Requirements
- **Financial Precision:** Request costs are calculated based on fractional token units. All rate limiting calculations MUST use `decimal.Decimal` to avoid floating-point precision loss.
- **Floating-point is strictly forbidden** for core quota calculations.

## 3. Data Types
- Quota: `decimal.Decimal`
- Cost: `decimal.Decimal`
