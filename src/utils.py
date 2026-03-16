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
