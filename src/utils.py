"""工具模块"""
from datetime import datetime
import json

def format_date(dt: datetime) -> str:
    """格式化日期为 YYYY-MM-DD"""
    return dt.strftime("%Y-%m-%d")

def parse_json(json_str: str) -> dict:
    """安全解析 JSON"""
    try:
        return json.loads(json_str)
    except json.JSONDecodeError:
        return {}

# Agent 1 添加的函数
def format_upper(text: str) -> str:
    """转大写"""
    return text.upper()

def format_lower(text: str) -> str:
    """转小写"""
    return text.lower()

# Agent 2 添加的函数
def format_reverse(text: str) -> str:
    """反转字符串"""
    return text[::-1]

def format_capitalize(text: str) -> str:
    """首字母大写"""
    return text.capitalize()
