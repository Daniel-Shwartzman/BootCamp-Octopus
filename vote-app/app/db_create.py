import os
from pymongo import MongoClient

def initialize_database():
    # Connection to MongoDB
    username = os.getenv('MONGO_ROOT_USERNAME')
    password = os.getenv('MONGO_ROOT_PASSWORD')
    database = os.getenv('MONGO_DATABASE')
    ip = os.getenv('MONGO_IP')

    mongo_uri = f'mongodb://{username}:{password}@{ip}:27017/'
    client = MongoClient(mongo_uri)
    db = client[database]

    # Check if the collections already exist
    if 'votes' not in db.list_collection_names():
        # Create a collection for votes
        votes_collection = db['votes']

        # Insert initial data for Trump and Biden
        initial_data = [
            {'candidate': 'Trump', 'count':  0},
            {'candidate': 'Biden', 'count':  0}
        ]
        votes_collection.insert_many(initial_data)

    if 'answers' not in db.list_collection_names():
        # Create a collection for answers
        answers_collection = db['answers']

        # Insert initial data for test_user
        initial_answers_data = [
            {'username': 'test_user', 'right_answers': 0, 'wrong_answers': 0}
        ]
        answers_collection.insert_many(initial_answers_data)

    print("Database initialized successfully.")

if __name__ == "__main__":
    initialize_database()