# Introduction:

 An easy way to do TESTOS provision and testing on physical machine.


 mastserver.py:

	This file need to be deployed on the control server and used to control the test
	server usage. During the testing, the program first need to check with
	control server whether server is using by the other user, if not, then
	notice the control server to lock the test machine and run testing. After finishing 
	the testing, the program notices the control server to unlock the test server.

 autophysion.sh:

	Run automatic provision TESTOS and testing, this program could control
	test server power management module, work with our private cobbler server
	to provison TESTOS, call the test case script to run the test case on 
	target TESTOS version and test server.

 ENV:

	The global environment parameter, you need customize some parameters in
	this file after you deploy this project to your place.

 phymachine.conf:

	Test servers configuration file.

 testcase.conf:

	Test cases configuration file.


# Getting started:

 1. Check necessary packages.

	./autophysion.sh -p


# Usage:

 1. First of all, you need make sure that the mastserver.py is already deployed and is
	running on the control server, if not, you need to deploy and running it

	Run:
		python2.7 mastserver.py

	Check if already running:
		curl -i http://${control server}:xxxx/check

 2. Print help message:

	$ sudo ./autophysion.sh -h

	Usage : ./autophysion.sh [OPTION]...
		-a Host Alias		Host Alias for provision, -l to show details.
		-c 			List all the test case for target machine.
		-d URL			Deploy target TESTOS profile on cobbler server.
		-l 			List all the physcial machines and xxx profiles on cobbler server.
		-m			List all the physical machines which can be provisioned.
		-n Host Cobbler Name	Host Cobbler Name for provision.
		-i 			Install TESTOS only, must work with -t option attach one case id.
		-p 			Check the necessary packages whether exist.
		-r TESTOS Version	TESTOS Version, please provide the unique TESTOS version name.
		-t [C3|C6|C9....]	Work with -a and -r option to run the given test case.
		-h			Print this message.

