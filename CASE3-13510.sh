#!/bin/bash

sshpass -p "${TESTHOSTNewPasswd}" ssh root@${HOSTIPAddr} -o StrictHostKeyChecking=no "
echo ----------------------TESTOS version--------------------------
cat /etc/*-release
echo ---------------------------rpm------------------------------
rpm -qa
echo --------------------------------------------------------------
" > ${TESTCASELOG}/${CASEPolarionID}.output 2>&1

scp_output=$(/usr/bin/expect <<-EOF
	set timeout ${expect_timeout}
	spawn -noecho scp -o StrictHostKeyChecking=no root@${HOSTIPAddr}:/var/log/*.log ${TESTCASELOG}/;
	expect {
		"s password:" {
			send -- "${TESTHOSTNewPasswd}\r"
		}
	}
	expect eof
	EOF
)

exit 0
