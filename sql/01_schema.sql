-- ============================================================
-- P1 · 실시간 금융 거래 이상탐지 대시보드
-- 파일: 01_schema.sql
-- 작성일: 2026-04-07 (D1 / W1)
-- 작성자: SONG
--
-- SQLD 커버리지:
--   - 정규화 (3NF): transactions ↔ fraud_scores 분리
--   - 인덱스 설계: B-tree (시간), 복합 인덱스 (amount 범위 쿼리)
--   - Materialized View: 집계 성능 최적화
-- ============================================================

-- 확장 설치 (최초 1회)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- 0. 스키마 초기화 (개발 환경 재실행용)
-- ============================================================
DROP TABLE IF EXISTS fraud_scores CASCADE;
DROP TABLE IF EXISTS transactions CASCADE;
DROP MATERIALIZED VIEW IF EXISTS mv_hourly_fraud_stats;
DROP MATERIALIZED VIEW IF EXISTS mv_daily_summary;

-- ============================================================
-- 1. Dimension 테이블 — 없음 (PCA 익명 데이터 특성)
--    실제 프로덕션이라면: dim_merchant, dim_card_holder 분리
-- ============================================================

-- ============================================================
-- 2. Fact 테이블 — 거래 원본 데이터
-- ============================================================
CREATE TABLE transactions (
    -- 식별자
    txn_id          UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
    
    -- 원본 데이터셋 컬럼
    time_elapsed    FLOAT       NOT NULL,          -- 첫 거래 기준 경과 초
    amount          NUMERIC(12, 2) NOT NULL,        -- 거래 금액 (EUR)
    
    -- PCA 피처 (V1 ~ V28)
    v1  FLOAT, v2  FLOAT, v3  FLOAT, v4  FLOAT,
    v5  FLOAT, v6  FLOAT, v7  FLOAT, v8  FLOAT,
    v9  FLOAT, v10 FLOAT, v11 FLOAT, v12 FLOAT,
    v13 FLOAT, v14 FLOAT, v15 FLOAT, v16 FLOAT,
    v17 FLOAT, v18 FLOAT, v19 FLOAT, v20 FLOAT,
    v21 FLOAT, v22 FLOAT, v23 FLOAT, v24 FLOAT,
    v25 FLOAT, v26 FLOAT, v27 FLOAT, v28 FLOAT,
    
    -- 레이블 (학습용)
    class_label     SMALLINT    NOT NULL CHECK (class_label IN (0, 1)),
    
    -- 파생 피처 (EDA에서 생성한 항목)
    hour_of_day     SMALLINT    GENERATED ALWAYS AS
                    (FLOOR(time_elapsed / 3600)::INTEGER % 24) STORED,
    is_night        BOOLEAN     GENERATED ALWAYS AS
                    (FLOOR(time_elapsed / 3600)::INTEGER % 24 < 6
                     OR FLOOR(time_elapsed / 3600)::INTEGER % 24 >= 22) STORED,
    log_amount      FLOAT       GENERATED ALWAYS AS
                    (LN(amount + 1)) STORED,
    
    -- 메타데이터
    loaded_at       TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE transactions IS 'Kaggle mlg-ulb creditcardfraud 원본 데이터 + 파생 피처';
COMMENT ON COLUMN transactions.class_label IS '0=정상, 1=사기';
COMMENT ON COLUMN transactions.time_elapsed IS '데이터셋 첫 거래 기준 경과 초 (실제 타임스탬프 아님)';

-- ============================================================
-- 3. Fact 테이블 — ML 모델 스코어링 결과
-- ============================================================
CREATE TABLE fraud_scores (
    score_id        UUID        DEFAULT uuid_generate_v4() PRIMARY KEY,
    txn_id          UUID        NOT NULL REFERENCES transactions(txn_id),
    
    -- 모델 메타
    model_version   VARCHAR(20) NOT NULL DEFAULT 'xgb_v1',
    scored_at       TIMESTAMPTZ DEFAULT NOW(),
    
    -- 스코어
    fraud_prob      FLOAT       NOT NULL CHECK (fraud_prob BETWEEN 0 AND 1),
    is_fraud_pred   BOOLEAN     NOT NULL,  -- 임계값 적용 후 최종 판정
    threshold_used  FLOAT       NOT NULL DEFAULT 0.5,
    
    -- 설명 가능성 (SHAP - 상위 3개 피처)
    top_feature_1   VARCHAR(10),
    top_feature_2   VARCHAR(10),
    top_feature_3   VARCHAR(10),
    shap_value_1    FLOAT,
    shap_value_2    FLOAT,
    shap_value_3    FLOAT
);

COMMENT ON TABLE fraud_scores IS 'XGBoost 모델 스코어링 결과 및 SHAP 설명';

-- ============================================================
-- 4. 인덱스 설계 (SQLD: 복합 인덱스, 실행계획 최적화)
-- ============================================================

-- 시간 기반 조회 (대시보드 기본 필터)
CREATE INDEX idx_txn_time ON transactions (time_elapsed);
CREATE INDEX idx_txn_hour ON transactions (hour_of_day);

-- 클래스 필터 (사기 건만 빠르게 조회)
CREATE INDEX idx_txn_class ON transactions (class_label);

-- 금액 범위 쿼리
CREATE INDEX idx_txn_amount ON transactions (amount);

-- 복합 인덱스: 시간 + 클래스 (대시보드 핵심 쿼리)
CREATE INDEX idx_txn_hour_class ON transactions (hour_of_day, class_label);

-- 스코어 조회
CREATE INDEX idx_score_txn ON fraud_scores (txn_id);
CREATE INDEX idx_score_prob ON fraud_scores (fraud_prob DESC);
CREATE INDEX idx_score_pred ON fraud_scores (is_fraud_pred, scored_at DESC);

-- ============================================================
-- 5. Materialized View — 시간대별 사기 통계 (대시보드용)
-- ============================================================
CREATE MATERIALIZED VIEW mv_hourly_fraud_stats AS
SELECT
    hour_of_day,
    COUNT(*)                                        AS total_count,
    SUM(class_label)                                AS fraud_count,
    ROUND(AVG(class_label) * 100, 4)               AS fraud_rate_pct,
    ROUND(AVG(amount)::NUMERIC, 2)                 AS avg_amount,
    ROUND(SUM(amount)::NUMERIC, 2)                 AS total_amount
FROM transactions
GROUP BY hour_of_day
ORDER BY hour_of_day;

CREATE UNIQUE INDEX ON mv_hourly_fraud_stats (hour_of_day);

COMMENT ON MATERIALIZED VIEW mv_hourly_fraud_stats
IS '시간대별 사기 통계. 새 데이터 적재 후 REFRESH MATERIALIZED VIEW CONCURRENTLY 실행';

-- ============================================================
-- 6. Materialized View — 일별 요약 (포트폴리오 메인 대시보드)
-- ============================================================
CREATE MATERIALIZED VIEW mv_daily_summary AS
SELECT
    DATE_TRUNC('day', loaded_at)::DATE              AS date,
    COUNT(*)                                        AS total_txn,
    SUM(class_label)                                AS total_fraud,
    ROUND(AVG(class_label) * 100, 4)               AS fraud_rate_pct,
    ROUND(SUM(CASE WHEN class_label=1 THEN amount ELSE 0 END)::NUMERIC, 2)
                                                    AS fraud_amount_eur
FROM transactions
GROUP BY DATE_TRUNC('day', loaded_at)::DATE
ORDER BY date;

CREATE UNIQUE INDEX ON mv_daily_summary (date);

-- ============================================================
-- 7. SQLD 연습용 쿼리 모음
-- ============================================================

-- [SQLD] 윈도우 함수: 시간 순 누적 사기 건수
-- 직접 작성 권장: 이 쿼리가 '어떤 비즈니스 질문에 답하는지' 설명할 수 있어야 함
/*
SELECT
    txn_id,
    time_elapsed,
    amount,
    class_label,
    -- 누적 사기 건수
    SUM(class_label) OVER (
        ORDER BY time_elapsed
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_fraud_count,
    -- 직전 거래 금액 대비 변화율 (피처 엔지니어링)
    LAG(amount, 1) OVER (ORDER BY time_elapsed) AS prev_amount,
    ROUND(
        (amount - LAG(amount,1) OVER (ORDER BY time_elapsed))
        / NULLIF(LAG(amount,1) OVER (ORDER BY time_elapsed), 0) * 100, 2
    ) AS amount_change_pct,
    -- 최근 10건 평균 금액 (이상치 탐지 근거)
    ROUND(
        AVG(amount) OVER (
            ORDER BY time_elapsed
            ROWS BETWEEN 9 PRECEDING AND CURRENT ROW
        )::NUMERIC, 2
    ) AS rolling_avg_10
FROM transactions
ORDER BY time_elapsed
LIMIT 100;
*/

-- [SQLD] GROUPING SETS: 시간대·사기여부 다차원 집계
/*
SELECT
    hour_of_day,
    class_label,
    COUNT(*)            AS cnt,
    ROUND(AVG(amount)::NUMERIC, 2) AS avg_amount,
    GROUPING(hour_of_day) AS grp_hour,
    GROUPING(class_label) AS grp_class
FROM transactions
GROUP BY GROUPING SETS (
    (hour_of_day, class_label),
    (hour_of_day),
    (class_label),
    ()
)
ORDER BY hour_of_day NULLS LAST, class_label NULLS LAST;
*/

-- [SQLD] CTE: 이상 거래 탐지 (금액이 해당 시간대 평균의 N배 초과)
/*
WITH hourly_stats AS (
    SELECT
        hour_of_day,
        AVG(amount)    AS avg_amount,
        STDDEV(amount) AS std_amount
    FROM transactions
    WHERE class_label = 0  -- 정상 거래 기준
    GROUP BY hour_of_day
),
flagged AS (
    SELECT
        t.txn_id,
        t.time_elapsed,
        t.amount,
        t.hour_of_day,
        t.class_label,
        h.avg_amount,
        h.std_amount,
        ROUND(((t.amount - h.avg_amount) / NULLIF(h.std_amount, 0))::NUMERIC, 3) AS z_score
    FROM transactions t
    JOIN hourly_stats h USING (hour_of_day)
)
SELECT *
FROM flagged
WHERE z_score > 3  -- 3 시그마 초과 → 이상 의심
ORDER BY z_score DESC
LIMIT 50;
*/

-- ============================================================
-- 8. 데이터 로드 확인 쿼리 (데이터 적재 후 실행)
-- ============================================================
/*
-- 기본 확인
SELECT
    COUNT(*)                                AS total_rows,
    SUM(class_label)                        AS fraud_rows,
    ROUND(AVG(class_label)*100, 4)         AS fraud_pct,
    ROUND(AVG(amount)::NUMERIC, 2)         AS avg_amount,
    MIN(time_elapsed)                       AS min_time,
    MAX(time_elapsed)                       AS max_time
FROM transactions;

-- 기대 결과:
-- total_rows: 284807
-- fraud_rows: 492
-- fraud_pct: 0.1727
*/
