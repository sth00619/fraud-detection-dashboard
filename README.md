# P1 · 실시간 금융 거래 이상탐지 대시보드

> **상태:** 🔨 W1 진행 중 (2026-04-07 ~)  
> **목표 완료:** W2 (2026-04-19)  
> **스택:** XGBoost · Airflow · FastAPI · Redis · PostgreSQL · Recharts

---

## 문제 정의

이커머스·핀테크 플랫폼에서 **사기 거래(Fraud)로 인한 차지백(Chargeback) 비용**이 지속 증가하고 있다. 기존 규칙 기반(rule-based) 시스템은 고정 임계값에 의존하여 **재현율(Recall)이 낮고**, 새로운 사기 패턴에 적응하지 못한다.

**핵심 비즈니스 질문:**
- 어떤 거래가 사기일 확률이 높은가?
- 임계값을 어느 수준으로 설정해야 비용(미탐지 vs 과탐지)을 최소화할 수 있는가?
- 실시간 스코어링 결과를 운영팀이 모니터링할 수 있는가?

---

## 데이터셋

| 항목 | 내용 |
|------|------|
| 출처 | [Kaggle — Credit Card Fraud Detection (mlg-ulb)](https://www.kaggle.com/datasets/mlg-ulb/creditcardfraud) |
| 크기 | 284,807 rows × 31 columns (약 144 MB) |
| 기간 | 2013년 9월 유럽 카드 거래 (2일치) |
| 라이센스 | DbCL (Database Contents License) |
| 불균형 | 사기 492건 (0.172%) / 정상 284,315건 |

### 컬럼 구조

| 컬럼 | 타입 | 설명 |
|------|------|------|
| Time | float | 첫 거래 기준 경과 초 |
| V1 ~ V28 | float | PCA 변환 익명 피처 (기밀 보호) |
| Amount | float | 거래 금액 (EUR) |
| Class | int | 0=정상, 1=사기 |

> ⚠️ **데이터 한계:** V1~V28은 PCA 익명 처리로 비즈니스 해석 불가. 2013년 2일치 스냅샷으로 시계열 일반화 한계 있음.

---

## 아키텍처

```
[CSV 원본]
    ↓ Python (pandas)
[PostgreSQL]  ←──  Airflow DAG (일배치)
    ↓ SQL Window Functions
[Feature Store]
    ↓
[XGBoost 모델]  →  FastAPI (/predict)
    ↓
[Redis 캐시]  →  Next.js 대시보드 (Recharts)
```

---

## 진행 단계

| 단계 | 작업 | 상태 | 파일 |
|------|------|------|------|
| 1-1 | 데이터셋 확보 및 검증 | ✅ | — |
| 1-2 | EDA | 🔨 | `notebooks/01_eda.ipynb` |
| 1-3 | DB 스키마 설계 | ✅ | `sql/01_schema.sql` |
| 1-4 | SQLD 쿼리 구현 | 🔨 | `sql/01_schema.sql` |
| 2-1 | 피처 엔지니어링 | ⬜ | — |
| 2-2 | XGBoost 모델링 | ⬜ | — |
| 2-3 | Airflow DAG | ⬜ | — |
| 2-4 | FastAPI 스코어링 | ⬜ | — |
| 2-5 | Redis 캐싱 | ⬜ | — |
| 2-6 | 대시보드 (Recharts) | ⬜ | — |

---

## 기술 선택 근거

### XGBoost를 선택한 이유
- `scale_pos_weight` 파라미터로 **클래스 불균형 직접 처리** 가능
- 트리 기반 앙상블 → **결측치 처리 내장**, PCA 피처에 강건
- SHAP 라이브러리와 네이티브 호환 → **예측 설명 가능성** 확보
- 대안: Logistic Regression(해석 쉽지만 비선형 패턴 취약), Random Forest(느림)

### imbalanced-learn (SMOTE) 선택 이유
- 0.172% 불균형 → 단순 학습 시 모델이 '전부 정상'으로 예측해도 99.8% 정확도
- SMOTE로 소수 클래스 오버샘플링 → **Recall 우선 최적화**
- 적용 순서: Train split 후 → Train에만 SMOTE (Test set 오염 방지)

### 평가 지표: F2-Score
- Precision-Recall 트레이드오프에서 **Recall에 2배 가중치**
- 근거: 사기 미탐지(False Negative) 비용 > 정상 거래 차단(False Positive) 비용

---

## 라이브러리 매핑

| 라이브러리 | 버전 | 역할 |
|----------|------|------|
| pandas | 2.x | 데이터 전처리, EDA |
| numpy | 1.26+ | 수치 연산 |
| scikit-learn | 1.4+ | 전처리, 평가 지표, train-test split |
| xgboost | 2.x | 이상탐지 분류 모델 |
| imbalanced-learn | 0.12+ | SMOTE 오버샘플링 |
| shap | 0.45+ | 모델 설명 (Feature Importance) |
| FastAPI | 0.110+ | 실시간 스코어링 REST API |
| Redis (redis-py) | 5.x | 예측 결과 캐싱 |
| Apache Airflow | 2.9+ | 배치 파이프라인 오케스트레이션 |
| PostgreSQL | 16 | 거래 원본 + 스코어 저장 |

---

## 자격증 커버리지

### SQLD 활용 항목
- **윈도우 함수:** `LAG()`, `SUM() OVER()`, `AVG() OVER()` → 거래 패턴 피처 생성
- **GROUPING SETS:** 시간대 × 클래스 다차원 집계 (대시보드 통계)
- **CTE:** Z-score 기반 이상 거래 탐지 쿼리
- **Materialized View:** 시간대별 사기 통계 캐싱 (API 응답 속도 최적화)
- **복합 인덱스:** `(hour_of_day, class_label)` → 대시보드 필터 쿼리 최적화

### ADsP 활용 항목
- **분류분석:** XGBoost 이진 분류 (사기/정상)
- **가설검정:** 임계값 변화에 따른 F2-Score 유의성 검증

---

## 개발 방식

| 구분 | 작업 내용 |
|------|----------|
| **직접 작성** | EDA 인사이트 해석, 임계값 선정 로직 (F2 기준), 모델 하이퍼파라미터 의사결정, SHAP 해석 |
| **Claude Code 활용** | Airflow DAG 보일러플레이트, Docker Compose 설정, FastAPI 엔드포인트 스캐폴딩 |

> **면접 답변:** "파이프라인 보일러플레이트는 Claude Code로 빠르게 잡고, 임계값 설정·모델 선택·인사이트 도출은 직접 작성합니다. 코드가 왜 그렇게 작동하는지 설명할 수 없는 부분은 절대 사용하지 않습니다."

---

## 면접 대비 핵심 질문

**Q1. 왜 Accuracy를 쓰지 않고 F2-Score를 사용했나요?**
> 클래스 비율이 0.172%인 극단적 불균형 데이터에서 '전부 정상으로 예측'해도 Accuracy 99.8%가 나옵니다. 비즈니스 관점에서 사기를 놓치는 비용(False Negative)이 정상 거래를 막는 비용(False Positive)보다 크기 때문에, Recall에 2배 가중치를 주는 F2-Score를 선택했습니다.

**Q2. SMOTE를 Train에만 적용한 이유는?**
> Test set에 SMOTE를 적용하면 합성 데이터가 평가에 포함되어 실제 성능보다 과대평가됩니다. 반드시 Train/Test split 후 Train에만 SMOTE를 적용해야 현실적인 성능 측정이 가능합니다.

**Q3. 이 모델을 실 서비스에 배포한다면 어떤 추가 작업이 필요한가요?**
> (1) 개념 드리프트 모니터링(시간에 따른 사기 패턴 변화 감지), (2) A/B 테스트로 임계값 변경 효과 검증, (3) 모델 재학습 파이프라인 자동화, (4) 오탐지 피드백 루프 구축이 필요합니다.

---

## 폴더 구조

```
p1-fraud-detection/
├── data/
│   └── .gitkeep              # CSV는 Git LFS 또는 .gitignore 처리
├── notebooks/
│   └── 01_eda.ipynb          # ← 오늘 작업
├── sql/
│   └── 01_schema.sql         # ← 오늘 작업
├── src/
│   ├── pipeline/             # Airflow DAG (W2)
│   ├── model/                # XGBoost 학습 (W2)
│   └── api/                  # FastAPI (W2)
├── docs/
│   └── img/                  # EDA 시각화 이미지
├── docker-compose.yml        # (W2)
└── README.md
```

---

## 커밋 로그

```
[P1] data: verify creditcard dataset (284807 rows, 31 cols, 0 nulls)
[P1] sql: add PostgreSQL schema with window function queries
[P1] eda: add EDA notebook (class imbalance, time/amount analysis)
```

---

*최종 업데이트: 2026-04-07*
