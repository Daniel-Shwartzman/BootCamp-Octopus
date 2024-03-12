import os
from flask import Flask, render_template, request, redirect, url_for, abort
from pymongo import MongoClient

# Getting the environment variables from the secrets file
mongo_username = os.getenv('MONGO_ROOT_USERNAME')
mongo_password = os.getenv('MONGO_ROOT_PASSWORD')
mongo_ip = os.getenv('MONGO_IP')
mongo_db = os.getenv('MONGO_DATABASE')

# Establishing connection to mongo database
mongo_uri = f'mongodb://{mongo_username}:{mongo_password}@{mongo_ip}:27017/{mongo_db}?authSource=admin'
client = MongoClient(mongo_uri)
db = client[mongo_db]

app = Flask(__name__)

# Home page
@app.route('/')
def home():
    return render_template('home.html')

# Collecting the username and the vote and adding the vote to the database
@app.route('/vote', methods=['POST'])
def vote():
    candidate = request.json['candidate']
    data = request.get_json()
    username = data['username']
    if candidate not in ['Trump', 'Biden']:
        abort(400)
    db.votes.update_one({'candidate': candidate}, {'$inc': {'votes': 1}}, upsert=True)
    return redirect(url_for('questions', username=username))

# Displaying the questions page according to the username
@app.route('/questions', methods=['GET'])
def questions():
    username = request.args.get('username')
    return render_template('questions.html', username=username)

# Submitting the answers and adding the answers and the username to the database
@app.route('/submit-answers', methods=['POST'])
def submit_answers():
    correct_answers = ['Trump', 'Trump', 'Trump', 'Trump', 'Biden', 'Trump', 'Biden', 'Trump', 'Biden', 'Biden']  # actual correct answers
    user_answers = request.form.to_dict()
    username = user_answers.pop('username')  # retrieve and remove the username from the answers
    right_answers = sum(user_answer == correct_answer for user_answer, correct_answer in zip(user_answers.values(), correct_answers))
    wrong_answers = len(user_answers) - right_answers
    db.answers.insert_one({'username': username, 'right_answers': right_answers, 'wrong_answers': wrong_answers})
    return redirect(url_for('results'))

# Getting the results of the votes and the answers
@app.route('/results', methods=['GET'])
def results():
    trump_doc = db.votes.find_one({'candidate': 'Trump'})
    biden_doc = db.votes.find_one({'candidate': 'Biden'})

    # Getting the votes for each candidate or setting it to 0 if it is the first vote
    trump_votes = trump_doc['votes'] if trump_doc else 0
    biden_votes = biden_doc['votes'] if biden_doc else 0

    users_data = list(db.answers.find({'username': {'$ne': 'test_user'}}))
    return render_template('results.html', trump_votes=trump_votes, biden_votes=biden_votes, users_data=users_data)

if __name__ == '__main__':
    app.run(debug=True)