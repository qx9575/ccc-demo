# ============ 测试脚本快照 ============
# 原始路径: tests/test_calculator.py
# 任务: task-005
# 归档时间: 2026-03-25T11:41:58Z
# 归档者: archive-system
# ====================================

"""计算器模块测试"""

import sys
sys.path.insert(0, 'src')

from calculator import add, subtract, multiply, divide


def test_add():
    """测试加法"""
    assert add(1, 2) == 3
    assert add(-1, 1) == 0
    assert abs(add(0.1, 0.2) - 0.3) < 0.0001


def test_subtract():
    """测试减法"""
    assert subtract(5, 3) == 2
    assert subtract(1, 1) == 0
    assert subtract(0, 5) == -5


def test_multiply():
    """测试乘法"""
    assert multiply(2, 3) == 6
    assert multiply(-2, 3) == -6
    assert multiply(0, 100) == 0


def test_divide():
    """测试除法"""
    assert divide(6, 2) == 3
    assert divide(5, 2) == 2.5
    assert divide(-6, 2) == -3


def test_divide_by_zero():
    """测试除零异常"""
    try:
        divide(1, 0)
        assert False, "应该抛出 ValueError"
    except ValueError as e:
        assert "除数不能为零" in str(e)


if __name__ == "__main__":
    test_add()
    print("✓ test_add 通过")
    test_subtract()
    print("✓ test_subtract 通过")
    test_multiply()
    print("✓ test_multiply 通过")
    test_divide()
    print("✓ test_divide 通过")
    test_divide_by_zero()
    print("✓ test_divide_by_zero 通过")
    print("\n所有测试通过!")
