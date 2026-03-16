"""Hello 模块 - 提供简单的问候功能"""


def say_hello(name: str) -> str:
    """
    生成问候语
    
    Args:
        name: 名字字符串
        
    Returns:
        问候语字符串，格式为 "Hello, {name}!"
    """
    return f"Hello, {name}!"
