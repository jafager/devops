import re

def test_hello_world(client):
    response = client.get('/')
    assert response.status_code == 200
    assert re.fullmatch(r"<p>Hello, world! The date and time is \d\d\d\d\-\d\d\-\d\d \d\d:\d\d:\d\d\.\d\d\d\d\d\d\.\.\.</p>", response.data.decode('utf-8')), f"Pattern not found in response body: {response.data.decode('utf-8')}"
