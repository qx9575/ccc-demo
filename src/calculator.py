"""计算器模块 - 提供基本算术运算"""


def add(a: float, b: float) -> float:
    """加法"""
    return a + b


def subtract(a: float, b: float) -> float:
    """减法"""
    return a - b


def multiply(a: float, b: float) -> float:
    """乘法"""
    return a * b


def divide(a: float, b: float) -> float:
    """
    除法
    
    Raises:
        ValueError: 当除数为零时
    """
    if b == 0:
        raise ValueError("除数不能为零")
    return a / b
