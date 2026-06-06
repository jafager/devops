from flask import Flask
from datetime import datetime

app = Flask(__name__)

@app.route('/')
def hello_world():
    return '<p>Hello, world! The date and time is {}...</p>'.format(datetime.now())
