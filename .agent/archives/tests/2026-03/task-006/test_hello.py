# ============ 测试脚本快照 ============
# 原始路径: tests/test_hello.py
# 任务: task-006
# 归档时间: 2026-03-25T12:40:30Z
# 归档者: archive-system
# ====================================

"""Hello 模块测试"""

import sys
sys.path.insert(0, 'src')

from hello import say_hello


def test_say_hello():
    """测试基本问候"""
    assert say_hello("World") == "Hello, World!"
    assert say_hello("Alice") == "Hello, Alice!"
    assert say_hello("Bob") == "Hello, Bob!"


def test_say_hello_empty():
    """测试空名字"""
    assert say_hello("") == "Hello, !"


def test_say_hello_unicode():
    """测试 Unicode 名字"""
    assert say_hello("世界") == "Hello, 世界!"
    assert say_hello("🎉") == "Hello, 🎉!"


if __name__ == "__main__":
    test_say_hello()
    test_say_hello_empty()
    test_say_hello_unicode()
    print("所有测试通过!")
