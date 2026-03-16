"""工具模块测试"""
import sys
sys.path.insert(0, 'src')
from datetime import datetime
from utils import format_date, parse_json

def test_format_date():
    dt = datetime(2026, 3, 16)
    assert format_date(dt) == "2026-03-16"

def test_parse_json():
    assert parse_json('{"a": 1}') == {"a": 1}
    assert parse_json('invalid') == {}

if __name__ == "__main__":
    test_format_date()
    print("✓ test_format_date 通过")
    test_parse_json()
    print("✓ test_parse_json 通过")
    print("\n所有测试通过!")
