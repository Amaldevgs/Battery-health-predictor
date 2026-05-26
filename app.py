# ================================================
# app.py — Battery Health Prediction API
# Battery Health Predictor | Ather Energy Project
# ================================================

from flask import Flask, request, jsonify
import joblib
import numpy as np
import pandas as pd

app = Flask(__name__)

# Load saved models
soh_model = joblib.load('soh_model.pkl')
rul_model = joblib.load('rul_model.pkl')

@app.route('/')
def home():
    return jsonify({
        'message': 'Battery Health Prediction API',
        'project': 'Ather Energy — Battery Health Predictor',
        'endpoints': {
            '/predict': 'POST — predict SOH and RUL',
            '/health': 'GET — check API status'
        }
    })

@app.route('/health')
def health():
    return jsonify({
        'status': 'running',
        'models': {
            'soh_model': 'loaded',
            'rul_model': 'loaded'
        }
    })

@app.route('/predict', methods=['POST'])
def predict():
    try:
        # Get input data from request
        data = request.get_json()

        # Extract features
        features = pd.DataFrame([{
            'cycle': data['cycle'],
            'voltage': data['voltage'],
            'temperature': data['temperature'],
            'capacity': data['capacity'],
            'degradation_pct': data.get('degradation_pct', 0),
            'voltage_drop': data.get('voltage_drop', 0),
            'soh_lag_1': data.get('soh_lag_1', 1.0),
            'soh_lag_3': data.get('soh_lag_3', 1.0),
            'temp_capacity': data['temperature'] * data['capacity'],
            'health_encoded': data.get('health_encoded', 2)
        }])

        # Make predictions
        predicted_soh = soh_model.predict(features)[0]
        predicted_rul = int(rul_model.predict(features)[0])

        # Determine health status
        if predicted_soh < 0.8:
            health_status = 'Critical'
        elif predicted_soh < 0.9:
            health_status = 'Warning'
        else:
            health_status = 'Healthy'

        return jsonify({
            'status': 'success',
            'predictions': {
                'predicted_soh': round(float(predicted_soh), 4),
                'predicted_rul': predicted_rul,
                'health_status': health_status,
                'degradation_pct': round((1 - float(predicted_soh)) * 100, 2)
            },
            'input_received': data
        })

    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 400

if __name__ == '__main__':
    app.run(debug=True, port=5000)