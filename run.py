@app.route('/health')
def health():
    return {'status': 'healthy'}, 200
