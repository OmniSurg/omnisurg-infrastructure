-- One logical database per OmniSurg Phase 1 service.
-- The default superuser created by the image owns these databases.
-- Each service connects with its own role created here.

CREATE ROLE omnisurg_identity LOGIN PASSWORD 'omnisurg-local-only';
CREATE ROLE omnisurg_tenant LOGIN PASSWORD 'omnisurg-local-only';
CREATE ROLE omnisurg_patient LOGIN PASSWORD 'omnisurg-local-only';
CREATE ROLE omnisurg_clinical LOGIN PASSWORD 'omnisurg-local-only';
CREATE ROLE omnisurg_referral LOGIN PASSWORD 'omnisurg-local-only';
CREATE ROLE omnisurg_billing LOGIN PASSWORD 'omnisurg-local-only';
CREATE ROLE omnisurg_payment LOGIN PASSWORD 'omnisurg-local-only';
CREATE ROLE omnisurg_claims LOGIN PASSWORD 'omnisurg-local-only';
CREATE ROLE omnisurg_notification LOGIN PASSWORD 'omnisurg-local-only';
CREATE ROLE omnisurg_scheduling LOGIN PASSWORD 'omnisurg-local-only';
CREATE ROLE omnisurg_audit LOGIN PASSWORD 'omnisurg-local-only';
CREATE ROLE omnisurg_currency LOGIN PASSWORD 'omnisurg-local-only';

CREATE DATABASE omnisurg_identity OWNER omnisurg_identity;
CREATE DATABASE omnisurg_tenant OWNER omnisurg_tenant;
CREATE DATABASE omnisurg_patient OWNER omnisurg_patient;
CREATE DATABASE omnisurg_clinical OWNER omnisurg_clinical;
CREATE DATABASE omnisurg_referral OWNER omnisurg_referral;
CREATE DATABASE omnisurg_billing OWNER omnisurg_billing;
CREATE DATABASE omnisurg_payment OWNER omnisurg_payment;
CREATE DATABASE omnisurg_claims OWNER omnisurg_claims;
CREATE DATABASE omnisurg_notification OWNER omnisurg_notification;
CREATE DATABASE omnisurg_scheduling OWNER omnisurg_scheduling;
CREATE DATABASE omnisurg_audit OWNER omnisurg_audit;
CREATE DATABASE omnisurg_currency OWNER omnisurg_currency;
