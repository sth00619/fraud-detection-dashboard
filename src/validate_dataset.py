"""
P1 · 데이터셋 검증 스크립트
파일: src/validate_dataset.py
실행: python src/validate_dataset.py

EDA 노트북 실행 전 데이터가 올바르게 다운로드됐는지 확인합니다.
직접 작성 권장: 검증 조건(assert)의 기댓값은 본인이 이해하고 설정해야 함
"""

import sys
from pathlib import Path

def validate_creditcard_dataset(data_path: str = "data/creditcard.csv") -> bool:
    """
    creditcard.csv 데이터셋 검증
    
    검증 항목:
    1. 파일 존재 여부
    2. Shape (284807 rows, 31 cols)
    3. 결측치 0개
    4. 클래스 분포 (사기 492건, 0.172%)
    5. 컬럼 목록
    """
    try:
        import pandas as pd
    except ImportError:
        print("❌ pandas 미설치. pip install pandas 실행 후 재시도")
        return False

    path = Path(data_path)
    
    # ── 1. 파일 존재 확인 ──────────────────────────
    print("=" * 50)
    print("P1 · creditcard.csv 데이터셋 검증")
    print("=" * 50)
    
    if not path.exists():
        print(f"❌ 파일 없음: {path.absolute()}")
        print("   kaggle datasets download -d mlg-ulb/creditcardfraud -p data/ 실행")
        return False
    
    file_size_mb = path.stat().st_size / 1e6
    print(f"✅ 파일 존재: {path} ({file_size_mb:.1f} MB)")

    # ── 2. 데이터 로드 ─────────────────────────────
    print("\n로딩 중...", end=" ")
    df = pd.read_csv(path)
    print("완료")

    # ── 3. Shape 검증 ──────────────────────────────
    expected_shape = (284807, 31)
    if df.shape != expected_shape:
        print(f"❌ Shape 불일치: {df.shape} (기대: {expected_shape})")
        return False
    print(f"✅ Shape: {df.shape} (284,807 rows × 31 cols)")

    # ── 4. 결측치 확인 ─────────────────────────────
    null_count = df.isnull().sum().sum()
    if null_count != 0:
        print(f"❌ 결측치 {null_count}개 발견")
        print(df.isnull().sum()[df.isnull().sum() > 0])
        return False
    print(f"✅ 결측치: 0개")

    # ── 5. 클래스 분포 확인 ────────────────────────
    fraud_count = df["Class"].sum()
    total_count = len(df)
    fraud_pct = fraud_count / total_count * 100
    
    if fraud_count != 492:
        print(f"❌ 사기 건수 불일치: {fraud_count} (기대: 492)")
        return False
    print(f"✅ 사기 건수: {fraud_count:,} / {total_count:,} ({fraud_pct:.3f}%)")
    print(f"   불균형 비율: 정상:사기 = {(total_count - fraud_count) // fraud_count}:1")

    # ── 6. 컬럼 목록 확인 ─────────────────────────
    expected_cols = ["Time"] + [f"V{i}" for i in range(1, 29)] + ["Amount", "Class"]
    if list(df.columns) != expected_cols:
        print(f"❌ 컬럼 불일치")
        print(f"   실제: {list(df.columns)}")
        return False
    print(f"✅ 컬럼: Time, V1~V28, Amount, Class (31개)")

    # ── 7. 기본 통계 출력 ─────────────────────────
    print("\n── 거래금액 통계 ────────────────────")
    amount_stats = df.groupby("Class")["Amount"].agg(["mean", "median", "max"])
    amount_stats.index = ["정상 (0)", "사기 (1)"]
    print(amount_stats.round(2).to_string())

    print("\n── 시간 범위 ────────────────────────")
    print(f"   최소: {df['Time'].min():.0f}초")
    print(f"   최대: {df['Time'].max():.0f}초 ({df['Time'].max()/3600:.1f}시간)")

    print("\n" + "=" * 50)
    print("✅ 데이터셋 검증 완료 — EDA 노트북을 실행하세요")
    print("=" * 50)
    return True


if __name__ == "__main__":
    data_path = sys.argv[1] if len(sys.argv) > 1 else "data/creditcard.csv"
    success = validate_creditcard_dataset(data_path)
    sys.exit(0 if success else 1)
