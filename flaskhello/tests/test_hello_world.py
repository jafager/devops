from src.app import hello_world

def test_hello_world():
    assert hello_world() == '<p>Hello, world!</p>'
