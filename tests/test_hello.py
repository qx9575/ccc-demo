\"\"\"\
测试 hello 模块\
\"\"\"\
import unittest\
from src.hello import greet, main\
\
\
class TestHello(unittest.TestCase):\
    \"\"\"测试 Hello 模块\"\"\"\
\
    def test_greet_with_name(self):\
        \"\"\"测试带名字的问候\"\"\"\
        result = greet(\"Python\")\
        self.assertEqual(result, \"Hello, Python!\")\
\
    def test_greet_with_empty_name(self):\
        \"\"\"测试空名字\"\"\"\
        result = greet(\"\")\
        self.assertEqual(result, \"Hello, !\")\
\
    def test_greet_with_world(self):\
        \"\"\"测试默认 World 名字\"\"\"\
        result = greet(\"World\")\
        self.assertEqual(result, \"Hello, World!\")\
\
    def test_main_function(self):\
        \"\"\"测试主函数\"\"\"\
        result = main()\
        self.assertEqual(result, \"Hello, World!\")\
\
\
if __name__ == \"__main__\":\
    unittest.main()
