\"\"\"\
简单的问候模块\
\"\"\"\
\
\
def greet(name: str) -> str:\
    \"\"\"返回问候语\"\"\"\
    return f\"Hello, {name}!\"\
\
\
def main():\
    \"\"\"主函数\"\"\"\
    message = greet(\"World\")\
    print(message)\
    return message\
\
\
if __name__ == \"__main__\":\
    main()
