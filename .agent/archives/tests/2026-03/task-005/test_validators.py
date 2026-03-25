# ============ 测试脚本快照 ============
# 原始路径: tests/test_validators.py
# 任务: task-005
# 归档时间: 2026-03-25T11:41:58Z
# 归档者: archive-system
# ====================================

"""验证器模块测试"""
import sys
sys.path.insert(0, 'src')
from validators import validate_email, validate_phone

def test_validate_email():
    assert validate_email("test@example.com") == True
    assert validate_email("invalid") == False

def test_validate_phone():
    assert validate_phone("13812345678") == True
    assert validate_phone("12345") == False

if __name__ == "__main__":
    test_validate_email()
    print("✓ test_validate_email 通过")
    test_validate_phone()
    print("✓ test_validate_phone 通过")
    print("\n所有测试通过!")
