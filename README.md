# 실시간 금융 거래 이상탐지 대시보드

> 59만 건 거래 데이터에서 Isolation Forest + XGBoost A/B 테스트로 사기 탐지 F1 스코어를 0.12 → 0.41로 개선

## 📌 문제 정의
<!-- 배경, 비즈니스 질문, 성공 지표를 여기에 작성하세요 -->

## 🏗️ 아키텍처

```
[데이터 소스] → [ETL 파이프라인] → [DB/저장소] → [ML 모델] → [API] → [프론트엔드]
```

## 🔧 기술 스택

| Layer | Stack |
|-------|-------|
| Pipeline | Apache Airflow, Python, PySpark |
| ML | Isolation Forest, XGBoost, scikit-learn, SMOTE |
| Backend | FastAPI, SQLAlchemy |
| DB | PostgreSQL 16, Redis 7, MinIO |
| Frontend | Next.js 14, Recharts, Mapbox GL JS |
| Infra | Docker Compose, GitHub Actions |

## 📊 핵심 인사이트
<!-- 분석 결과 및 시각화를 여기에 추가하세요 -->

## 🚀 실행 방법

```bash
git clone https://github.com/sth00619/fraud-detection-dashboard.git
cd fraud-detection-dashboard
docker-compose up -d
```

## 📂 프로젝트 구조

```
fraud-detection-dashboard/
├── pipeline/         # Airflow DAG / Prefect Flow
├── backend/          # FastAPI or Spring Boot
├── frontend/         # Next.js
├── ml/               # 모델 학습 및 서빙
├── db/               # 스키마 및 마이그레이션
└── docker-compose.yml
```

## 🔗 배포 URL
<!-- https://your-app.railway.app -->

## ⚠️ 한계와 다음 단계
<!-- 데이터 한계, 개선 방향 등 -->
