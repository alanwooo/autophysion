from flask import Flask, jsonify, abort, request

app = Flask(__name__)

machines = [ ]
"""
machines = [ 
    {   
        'user': u'xxx',
        'machine': u'MACHINE_H1', 
    },  
]
"""

@app.route('/check', methods=['GET'])
def get_machines():
	return jsonify({'machines': machines})

@app.route('/check/<string:machine_name>', methods=['GET'])
def get_machine(machine_name):
	machine = filter(lambda t: t['machine'] == machine_name, machines)
	if len(machine) == 0:
		abort(404)
	return jsonify({'machine': machine[0]})

@app.route('/check', methods=['POST'])
def create_machine():
	if not request.json or not 'user' in request.json or not 'machine' in request.json:
		abort(400)
	machine = {
		'user': request.json['user'],
		'machine': request.json.get('machine', ""),
	}
	for mn in machines:
		if mn['user'] == machine['user']:
			return jsonify({'machine': machine}), 201
	machines.append(machine)
	return jsonify({'machine': machine}), 201

@app.route('/check/<string:machine_name>', methods=['DELETE'])
def delete_machine(machine_name):
	machine = filter(lambda t: t['machine'] == machine_name, machines)
	if len(machine) == 0:
		abort(404)
	machines.remove(machine[0])
	return jsonify({'result': True})

if __name__ == '__main__':
	app.run(host="0.0.0.0",port=9999 ,debug=True)

