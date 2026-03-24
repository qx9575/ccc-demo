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

# Agent 2 添加的函数
def format_reverse(text: str) -> str:
    """Agent 2: 反转字符串"""
    return text[::-1]

def format_capitalize(text: str) -> str:
    """Agent 2: 首字母大写"""
    return text.capitalize()
