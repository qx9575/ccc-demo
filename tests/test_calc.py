\"\"\"\
计算器模块测试\
\"\"\"\
\
import pytest\
from src.calc import multiply\
\
\
class TestMultiply:\
    \"\"\"multiply 函数测试\"\"\"\
    \
    def test_multiply_positive_numbers(self):\
        \"\"\"测试正数乘法\"\"\"\
        assert multiply(3, 4) == 12\
        assert multiply(5, 7) == 35\
    \
    def test_multiply_negative_numbers(self):\
        \"\"\"测试负数乘法\"\"\"\
        assert multiply(-3, 4) == -12\
        assert multiply(-2, -5) == 10\
    \
    def test_multiply_zero(self):\
        \"\"\"测试与零相乘\"\"\"\
        assert multiply(0, 5) == 0\
        assert multiply(10, 0) == 0\
    \
    def test_multiply_floats(self):\
        \"\"\"测试浮点数乘法\"\"\"\
        assert multiply(2.5, 4) == 10.0\
        assert multiply(1.5, 2.0) == 3.0\
    \
    def test_multiply_large_numbers(self):\
        \"\"\"测试大数乘法\"\"\"\
        assert multiply(1000000, 1000000) == 1000000000000
