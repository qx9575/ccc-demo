# ============ 测试脚本快照 ============
# 原始路径: tests/test_utils.py
# 任务: task-006
# 归档时间: 2026-03-25T12:40:30Z
# 归档者: archive-system
# ====================================

"""工具模块测试"""
import sys
sys.path.insert(0, 'src')
from datetime import datetime
from utils import format_date, parse_json, format_upper, format_lower, format_reverse, format_capitalize

def test_format_date():
    dt = datetime(2026, 3, 24)
    assert format_date(dt) == "2026-03-24"

def test_parse_json():
    assert parse_json('{"a": 1}') == {"a": 1}
    assert parse_json('invalid') == {}

def test_format_upper():
    assert format_upper("hello") == "HELLO"

def test_format_lower():
    assert format_lower("HELLO") == "hello"

def test_format_reverse():
    assert format_reverse("hello") == "olleh"

def test_format_capitalize():
    assert format_capitalize("hello") == "Hello"

if __name__ == "__main__":
    test_format_date()
    print("✓ test_format_date 通过")
    test_parse_json()
    print("✓ test_parse_json 通过")
    test_format_upper()
    print("✓ test_format_upper 通过")
    test_format_lower()
    print("✓ test_format_lower 通过")
    test_format_reverse()
    print("✓ test_format_reverse 通过")
    test_format_capitalize()
    print("✓ test_format_capitalize 通过")
    print("\n所有测试通过!")
