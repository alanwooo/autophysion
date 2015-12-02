#!/bin/bash

# Environment parameters
. ENV

# Packages
declare -A CMD_RPM
CMD_RPM=([nmap]='nmap' [expect]='expect' [sshpass]='sshpass' [uuencode]='sharutils')

usage()
{
	cat << EOF
Usage : $0 [OPTION]... 
	-a Host Alias		Host Alias for provision, -l to show details.
	-c 			List all the test case for target machine.
	-d URL			Deploy target TESTOS profile on cobbler server.
	-l 			List all the physcial machines and TESTOS profiles on cobbler server.
	-m			List all the physical machines which can be provisioned.
	-n Host Cobbler Name	Host Cobbler Name for provision.
	-i 			Install TESTOS only, must work with -t option attach one case id.
	-p 			Check the necessary packages whether exist.
	-r TESTOS Version	TESTOS Version, please provide the unique TESTOS version name.
	-t [C3|C6|C9....]	Work with -a and -r option to run the given test case.
	-h			Print this message.
EOF
	exit 1
}

ping_check()
{
	if ping $1 -c 3 -w 30 >/dev/null 2>&1; then
		return 0
	else
		return 1
	fi
}
 
package_check()
{
	for cmd in ${!CMD_RPM[*]}; do
		if ! which ${cmd} > /dev/null 2>&1; then
			PKGSRPM="${CMD_RPM[$cmd]} ${PKGSRPM}"
		fi
	done

	if [ X"${PKGSRPM}" != X ]; then
		echo "RUN: yum install ${PKGSRPM}" 
		exit 1
	fi
	echo "INFO: All packages are installed."
	exit 0
}

cobbler_ctl()
{
	cobbler_action=$1
	cobbler_output=$(/usr/bin/expect <<-EOF
	set timeout ${expect_timeout};
	spawn -noecho ssh -o StrictHostKeyChecking=no root@${cobbler_server};
	expect {
		"password:" {
			send -- "${cobbler_passwd}\r"
		}
	}
	send -- "\r\r"
	expect {
		"\[root\@" { 
			send -- "cobbler system list | sed 's/ //g'| grep -xw \"${HOSTCobName}\" > /dev/null && ls /etc/r*\r"
			expect {
				"release" {
					set host_ack 'yes'
				}
			}
		}
	}
	send -- "\r\r"
	expect {
		"\[root\@" {
			send -- "cobbler profile list | sed 's/ //g' | grep -xw \"${TESTHOSTVersion}\" > /dev/null && ls /etc/r*\r"
			expect {
				"release" { 
					set profile_ack 'yes'
				}	
			}
		}
	}
	send -- "\r\r"
	if { [ info exists host_ack ] } {
		if { [ info exists profile_ack ] } {
			if { "${cobbler_action}" == "add" } {
				send -- "cobbler system edit --name=\"${HOSTCobName}\" --profile=\"${TESTHOSTVersion}\" --netboot-enabled=1 --kopts=\"${TESTHOSTKernelArg}\" \r"
			} else {
				send -- "cobbler system edit --name=\"${HOSTCobName}\" --netboot-enabled=0 \r"
			}
		} else {
			exit 100	
		}
	} else {
		exit 101
	}
	
	send -- "exit\r"
	expect eof {
		if { [ info exists host_ack ] } {
			unset host_ack
		}
		if { [ info exists profile_ack ] } {
			unset profile_ack
		}
	}
	EOF
)

	cobbler_exit_status=$?
	if [ ${cobbler_exit_status} -eq 101 ]; then
		echo -e "\nERROR: Cannot find the HOST profile on cobbler server :"
		echo "       HOST : ${HOSTCobName}"
		echo "       Please double check by the command : # cobbler system list"
		keep_test_machine 'unlock'
		exit 1
	fi
	if [ ${cobbler_exit_status} -eq 100 ]; then
		echo -e "\nERROR: Cannot fine the TESTOS profile on cobbler server :"
		echo "       TESTOS Version : ${TESTHOSTVersion}"
		echo "       Please double check by the command : # cobbler profile list"
		keep_test_machine 'unlock'
		exit 1
	fi
}

host_power_reset()
{
	host_output=$(/usr/bin/expect  <<-EOF
	set timeout ${expect_timeout}
	spawn -noecho ssh -o StrictHostKeyChecking=no ${HOSTMgtPater} ${HOSTMgtUserName}@${HOSTMgtIPAddr};
	expect {
		"password:" {
			send -- "${HOSTMgtPasswd}\r"
		}
	}
	send -- "\r\r"
	expect {
		"${HOSTMgtTypeiPtn}" {
			send -- "${HOSTMgtPowerReset}\r"
			expect {
				"${HOSTMgtPowerResetExpect}" {
					set host_reset 'yes'
				}
			}
		}
	}
	send -- "${HOSTMgtexit}\r\r"
	if { ! [ info exists host_reset ] } {
		exit 103
	}
	expect eof {
		if { [ info exists host_reset ] } {
			unset host_reset
		}
	}
	EOF
)
	#echo $host_output
	hostpower_exit_status=$?
	if [ ${hostpower_exit_status} -eq 103 ]; then
		echo -e "\nERROR: The system power restart failed. Please check manually."
		keep_test_machine 'unlock'
		exit 1
	fi
}

testhost_reset_passwd()
{
	reset_passwd_output=$(/usr/bin/expect <<-EOF 
	set timeout ${expect_timeout}
	spawn -noecho ssh -o StrictHostKeyChecking=no root@${HOSTIPAddr};
	expect {
		"s password:" {
			send -- "${TESTHOSTInitPasswd}\r"
			expect {
				"UNIX password:" {
					send -- "${TESTHOSTInitPasswd}\r"
					expect {
						"New password:" {
							send -- "${TESTHOSTNewPasswd}\r"
							expect "Retype new password:" {
								send -- "${TESTHOSTNewPasswd}\r"
							}
						}
					}
				}
			}
		}
	}
	send -- "\r\r"
	expect {
		"\[root\@" {
			send -- "ls\r"
		}
	}
	send -- "exit\r"
	expect eof
	EOF
)
}

testhost_verify()
{
	testhost_verify_output=$(/usr/bin/expect <<-EOF 
	set timeout ${expect_timeout}
	spawn -noecho ssh -o StrictHostKeyChecking=no root@${HOSTIPAddr};
	expect {
		"s password:" {
			send -- "${TESTHOSTNewPasswd}\r"
		}
	}
	send -- "\r\r"
	expect {
		"\[root\@" { 
			send -- "ls /etc/r*\r"
			expect {
				"release" {
					set testhost_ack 'yes'
				}
			}
		}
	}
	send -- "\r\r"
	if { ! [ info exists testhost_ack ] } {
		exit 102
	}
	send -- "exit\r"
	expect eof {
		if { [ info exists testhost_ack ] } {
			unset testhost_ack
		}
	}
	EOF
)
	testhostverify_exit_status=$?
	if [ ${testhostverify_exit_status} -eq 102 ]; then
		echo -e "\nERROR: TESTOS(${TESTHOSTVersion}) install or change password failed, stop all"
		echo "       the testings, please install and setup the TESTOS manually !"
		keep_test_machine 'unlock'
		exit 1
	fi
}

testhost_cobbler_profile_deploy()
{
	testhost_url=$1
	if ! echo ${testhost_url} | grep -w 'http' > /dev/null; then
		echo "ERROR: Please check the URL."
		exit 1
	fi

	TESTHOSTVersion=`echo ${testhost_url} | awk -F'/' '{ print $NF}'| grep "\.iso"`
	if [ X${TESTHOSTVersion} != X ]; then
		testhost_major_version=`echo ${TESTHOSTVersion} sed 's/-/\n/g' | egrep '6\.[0-9]|7\.[0-9]' | awk -F'.' '{ print $1 }'`
	else
		echo "ERROR: Please check the URL."
		exit 1
	fi

	testhost_exist=`sshpass -p "${cobbler_passwd}" ssh root@${cobbler_server} -o StrictHostKeyChecking=no cobbler profile list | sed 's/ //g' | grep -xw ${TESTHOSTVersion}`
	if [ X${testhost_exist} != X ]; then
		echo "INFO: TESTOS(${testhost_exist}) profile entry already exists."
		exit 0
	fi

	testhost_deploy_output=$(/usr/bin/expect <<-EOF
        set timeout ${expect_timeout};
        spawn -noecho ssh -o StrictHostKeyChecking=no root@${cobbler_server};
        expect {
                "password:" {
                        send -- "${cobbler_passwd}\r"
                }
        }
        send -- "\r\r"
        expect {
                "\[root\@" { 
			send -- "mkdir -p /home/igor-iso/${TESTHOSTVersion}\r"
        		send -- "\r"
			send -- "cd /home/igor-iso/${TESTHOSTVersion}\r"
        		send -- "\r"
                        send -- "wget -c \"${testhost_url}\" > /dev/null\r"
        		send -- "\r"
			send -- "ls\r"
			expect {
				"${TESTHOSTVersion}" {
					send -- "make_provision.py r ${testhost_major_version} /home/igor-iso/${TESTHOSTVersion}/${TESTHOSTVersion} --skip_plugin y\r\r"
				}
			}
		}
	}
	send -- "exit\r"
	expect eof
	EOF
)

        testhost_exist=`sshpass -p "${cobbler_passwd}" ssh root@${cobbler_server} -o StrictHostKeyChecking=no cobbler profile list | sed 's/ //g' | grep -xw ${TESTHOSTVersion}`
        if [ X${testhost_exist} != X ]; then
                echo "INFO: Deploy TESTOS(${testhost_exist}) profile successful."
                exit 0
        else
		echo "ERROR: Deploy TESTOS(${testhost_exist}) failed."
		exit 1
	fi
}

keep_test_machine()
{
	# GET:    curl -i ${MasterURL}/check/${HOSTAlias}
	# POST:   curl -i -H "Content-Type: application/json" -X POST -d '{"user":"'${USER}'","machine":"'${HOSTAlias}'"}' ${MasterURL}/check
	# DELETE: curl -i -X DELETE ${MasterURL}/check/${HOSTAlias}
	USER=`echo ${MAILTO} | awk -F'@' '{ print $1 }'`
	MasterURL="http://${MasterServer}:${MasterSerPort}"
	if [ $1 == 'lock' ]; then
		get_exit_code=`curl -s -w %{http_code} -o /dev/null ${MasterURL}/check/${HOSTAlias}`
		if [ ${get_exit_code} -eq 404 ];then
			post_exit_code=`curl -s -w %{http_code} -o /dev/null -H "Content-Type: application/json" -X POST -d '{"user":"'${USER}'","machine":"'${HOSTAlias}'"}' ${MasterURL}/check`
			if [ ${post_exit_code} -ne 201 ];then
				echo -e "\nERROR: Fail to keep the ${HOSTAlias}, please check master server."
				exit 1
			fi 
		elif [ ${get_exit_code} -eq 200 ]; then
			current_user=`curl -s ${MasterURL}/check/${HOSTAlias} | grep user | sed 's/"//g' | awk -F':' '{ print $2 }' | sed 's/ //g'`
			echo -e "\nERROR: ${HOSTAlias} is using by ${current_user}"
			exit 1
		else
			echo -e "\nERROR: Unknown error, please try command manually:"
			echo "       curl -i ${MasterURL}/check/${HOSTAlias}"
			exit 1
		fi
	else
		delete_exit_code=`curl -s -w %{http_code} -o /dev/null -X DELETE ${MasterURL}/check/${HOSTAlias}`
		if [ ${delete_exit_code} -ne 200 ]; then
			echo -e "\nWARNING: Failed to delete ${HOSTAlias} entry on master server."	
		fi
	fi	
}

exit_clean_install_failed()
{
	echo -e "\nINFO: Finished ${HOSTAlias}/${CASEPolarionID} testing ... FAIL!"
	exit 1
}

# # # # # # # # # # # # # # # # # main # # # # # # # # # # # # # # # #
export HOSTAlias
export HOSTCPUType
export HOSTCobName
export HOSTIPAddr
export TESTHOSTVersion
export CASEPolarionID

export expect_timeout=20
testhost_install_only=0
testcasetorun=C

if [ `id -u` -ne 0 ]; then
	echo "ERROR: Please run by root !"
	exit 1
fi

if [ $# == 0 ]; then
	usage
fi

while getopts "a:cd:hmn:ilpr:t:" OPTION; do
	case ${OPTION} in
		a)
			HOSTAlias=${OPTARG}
		;;
		c)
			cat ${TESTCASES} | grep -v "#" | sed '/^$/d' | grep -w "${HOSTAlias}"| awk -F? 'BEGIN{ 
					printf ("%-10s %-20s %-20s %-20s %-50s\n"),"ID","Machine Alias","Case Name","Script","Description";
					print "-------------------------------------------------------------------------"; } { 
					printf ("%-10s %-20s %-20s %-20s %-50s\n",$1,$2,$3,$6,$5);
				} END { printf "\n"; }'
			exit 0
				
		;;
		d)
			testhost_cobbler_profile_deploy ${OPTARG}
		;;
		h)
			usage
		;;
		l)
			echo "   Systems"
			echo "------------------------------------------------------------------------"
			sshpass -p "${cobbler_passwd}" ssh root@${cobbler_server} -o StrictHostKeyChecking=no cobbler system list | sed '1d'
			echo
			echo
			echo
			echo "   TESTOS Profiles"
			echo "------------------------------------------------------------------------"
			sshpass -p "${cobbler_passwd}" ssh root@${cobbler_server} -o StrictHostKeyChecking=no cobbler profile list | sed '1d'
			echo
			exit 0

		;;
		m)
			cat ${PHYMACHINE} | grep -v "#" | sed '/^$/d' | awk -F: 'BEGIN{
					printf ("%-20s %-25s %-50s\n"),"Alias","Cobbler Name","Description";
					print "-------------------------------------------------------------------------" } { 
					printf ("%-20s %-25s %-50s\n",$1,$2,$15)
				} END { printf "\n"; }'
			exit 0
		;;
		n)
			HOSTCobName=${OPTARG}
		;;
		i)
			testhost_install_only=1
		;;
		p)
			package_check
		;;
		r)
			TESTHOSTVersion=${OPTARG}
		;;
		t)
			if [ X${HOSTAlias} != X ]; then
				testcasetorun=${OPTARG}
				if echo ${testcasetorun} | sed 's/|/\n/g' | grep -v "C[0-9].*" > /dev/null; then
					echo "ERROR: Wrong args format."
					echo "       Please provide args like this:"
					echo "       $0 -a \${Host Alias} -r \${TESTOS Version} -t 'C1|C3|C4'"
					exit 1
				fi
			else
				echo "ERROR: The -t option must work with -a and -r option."
				exit 1
			fi
		;;
		\?)
			usage
		;;
	esac
done
#exit 1

rm -rf ${TESTCASELOG}/*
mkdir -p ${TESTCASELOG}

if [ X${TESTHOSTVersion} == X ]; then
	echo "ERROR: Please provide the TESTOS Version."
	exit 1
fi

check_testhost_profile=`sshpass -p "${cobbler_passwd}" ssh root@${cobbler_server} -o StrictHostKeyChecking=no cobbler profile list | sed 's/ //g' | grep ${TESTHOSTVersion}`
check_testhost_exist=`printf "${check_testhost_profile}\n" | wc -l`
if [ ${check_testhost_exist} -eq 1 ]; then
	TESTHOSTVersion=${check_testhost_profile}
else
	if [ ${check_testhost_exist} -eq 0 ]; then
		echo "ERROR: Cannot find the target TESTOS version on cobbler server."
		echo "       Please check manually."
		exit 1
	fi
	if [  ${check_testhost_exist} -gt 1 ]; then
		echo "ERROR: Please provide the exact TESTOS version name."
		exit 1
	fi
fi

if [ X${HOSTAlias} == X ]; then
	echo "ERROR: Please provide the machine alias."
	exit 1
else
	HOSTCobName=`cat ${PHYMACHINE} | grep -v "#" | grep -w "${HOSTAlias}" | awk -F: '{ print $2 }'`
	if [ ${HOSTCobName} == X ]; then
		echo "ERROR: Cannot fint the test machine alias. Run $0 -l"
		exit 1
	fi
fi
check_system_profile=`sshpass -p "${cobbler_passwd}" ssh root@${cobbler_server} -o StrictHostKeyChecking=no cobbler system list | sed 's/ //g' | grep ${HOSTCobName}`
check_system_exist=`printf "${check_system_profile}\n" | wc -l`
if [ ${check_system_exist} -eq 1 ]; then
        HOSTCobName=${check_system_profile}
else
        if [ ${check_system_exist} -eq 0 ]; then
                echo "ERROR: Cannot find the target TESTOS version on cobbler server."
                echo "       Please check manually."
                exit 1
        fi
        if [  ${check_system_exist} -gt 1 ]; then
                echo "ERROR: Please provide the exact TESTOS version."
                exit 1
        fi
fi

read HOSTAlias HOSTCPUType HOSTIPAddr HOSTMgtIPAddr HOSTMgtUserName HOSTMgtPasswd HOSTMgtTypeiPtn HOSTMgtexit < <( cat ${PHYMACHINE} | grep -v "#" | grep -w "${HOSTAlias}" | awk -F':' '{ print $1,$3,$5,$6,$7,$8,$10,$13 }' )
HOSTMgtPowerReset="`cat ${PHYMACHINE} | grep -v "#" | grep -w "${HOSTAlias}" | awk -F':' '{ print $11 }'`"
HOSTMgtPowerResetExpect="`cat ${PHYMACHINE} | grep -v "#" | grep -w "${HOSTAlias}" | awk -F':' '{ print $12 }'`"
HOSTMgtPater="`cat ${PHYMACHINE} | grep -v "#" | grep -w "${HOSTAlias}" | awk -F':' '{ print $14 }'`"


#cat ${TESTCASES} | grep -v "#" | grep -w "${HOSTAlias}" | egrep "${testcasetorun}" | while read testcase; do
testcasesfromfile=`cat ${TESTCASES} | grep -v "#" | grep -w "${HOSTAlias}" | egrep "${testcasetorun}" | awk -F'?' '{ print $1"?"$2"?"$3 }'`
testcasesnum=`printf "${testcasesfromfile}\n" | sed '/^$/d' | wc -l`
if [ ${testcasesnum} -eq 0 ]; then
	echo "ERROR: None test case selected, please check option or testcase.conf file, abort testing."
	exit 1
fi

trap "cobbler_ctl remove; keep_test_machine unlock; exit 1" 2
echo "---------------------------Testing start on ${HOSTAlias}-----------------------------------"
echo -e "INFO: Locking the test server ...\c"
keep_test_machine 'lock'
echo " Done!"
echo
echo
echo

(( testcasesnum = testcasesnum + 1 ))
lincase=1
while [ ${lincase} -lt ${testcasesnum} ]; do
	targetlincase=`printf "${testcasesfromfile}\n" | sed -n ${lincase}p`
	testcase=`cat ${TESTCASES} | grep ${targetlincase} | uniq`
	CASEID=`echo ${testcase} | awk -F'?' '{ print $1 }'`
	CASEPolarionID=`echo ${testcase} | awk -F'?' '{ print $3 }'`
	CASEKernelArgs="`echo ${testcase} | awk -F'?' '{ print $4 }'`"
	CASERunScript="`echo ${testcase} | awk -F'?' '{ print $6 }'`"
	TESTHOSTKernelArg="${CASEKernelArgs} ${TESTHOSTKernelBasedArg}"
	#echo ${CASEID}
	#echo ${CASEPolarionID}
	#echo ${CASEKernelArgs}
	#echo ${CASERunScript}
	#echo ${TESTHOSTKernelArg}

	if [ ${testhost_install_only} -ne 1 ]; then
		if [ ${CASERunScript} == 'None' ]; then
			echo "ERROR: There is not test script for ${CASEPolarionID}, skip this test case, continue next test case."
			continue
		fi
		echo "----------------------------Starting ${CASEPolarionID}------------------------------------"
	fi

	tmphostmgtipaddr=`echo ${HOSTMgtIPAddr} | sed 's/\./\\\./g'`
	tmphostipaddr=`echo ${HOSTIPAddr} | sed 's/\./\\\./g'`
	tmpcobbleripaddr=`echo ${cobbler_server} | sed 's/\./\\\./g'`
	sed -i '/'${tmphostmgtipaddr}'/d' ~/.ssh/known_hosts
	sed -i '/'${tmphostipaddr}'/d' ~/.ssh/known_hosts
	sed -i '/'${tmpcobbleripaddr}'/d' ~/.ssh/known_hosts

	echo -e "INFO: Rebooting the test server ...\c"
	host_power_reset
	sleep 3
	echo " Done!"
	
	echo -e "INFO: Checking if the server still alive ...\c"
	if ping_check ${HOSTIPAddr}; then
		sleep 600 &
		waittime=$!
		while [ -d /proc/${waittime} ]; do
			if ! ping_check ${HOSTIPAddr}; then
				break
			fi
			if [ ! -d /proc/${waittime} ]; then
				echo -e "\nERROR: Seems the server did not reboot, please check manually."
				keep_test_machine 'unlock'
				exit_clean_install_failed
			fi
			sleep 1
		done
	fi
	echo " Done!"

	echo -e "INFO: Configuring PXE boot ...\c"
	cobbler_ctl add
	sleep 9
	echo " Done!"

	# bu tong to tong
	echo -e "INFO: Waiting for server boot up to exec auto installation ...\c"
	i=0
	sleep 1800 &
	waittime=$!
	while [ -d /proc/${waittime} ]; do
		if ping_check ${HOSTIPAddr}; then
			(( i = i + 1 ))
			if [ ${i} -eq 3 ]; then
				cobbler_ctl remove
				break
			fi
		fi
		if [ ! -d /proc/${waittime} ]; then
			echo -e "\nERROR: Auto install failed, timeout to start auto installation."
			cobbler_ctl remove
			keep_test_machine 'unlock'
			exit_clean_install_failed
		fi
		sleep 1
	done
	echo " Done!"

	# tong to bu tong
	echo -e "INFO: Waiting for server finish auto installation and shutdown ...\c"
	j=0
	sleep 2400 &
	waittime=$!
	while [ -d /proc/${waittime} ]; do
		if ! ping_check ${HOSTIPAddr}; then
			(( j = j + 1 ))
			if [ ${j} -eq 3 ]; then
				break
			fi
		fi
		if [ ! -d /proc/${waittime} ]; then
			echo -e "\nERROR: Auto install failed, timeout to finish auto installation."
			keep_test_machine 'unlock'
			exit_clean_install_failed
		fi
		sleep 1
	done
	echo " Done!"

	# bu tong to tong
	echo -e "INFO: Waiting for server boot up after finished auto installation ...\c"
	sleep 10
	k=0
	sleep 1800 &
	waittime=$!
	while [ -d /proc/${waittime} ]; do
		if ping_check ${HOSTIPAddr}; then
			(( k = k + 1 ))
			if [ ${k} -eq 3 ]; then
				break
			fi
		fi
		if [ ! -d /proc/${waittime} ]; then
			echo -e "\nERROR: Auto install failed, timeout to the server boot up."
			keep_test_machine 'unlock'
			exit_clean_install_failed
		fi
		sleep 1
	done
	echo " Done!"

	# tong to ssh port tong
	echo -e "INFO: Waiting for ssh server start up, check port 22 whether ready for serving ...\c"
	sleep 600 &
	waittime=$!
	while [ -d /proc/${waittime} ]; do
		if nmap ${HOSTIPAddr} -p 22 | grep -w open > /dev/null 2>&1; then
 			break
		fi
		if [ ! -d /proc/${waittime} ]; then
			echo -e "\nERROR: Auto install failed, timeout to wait ssh service start."
			keep_test_machine 'unlock'
			exit_clean_install_failed
		fi
		sleep 10
	done
	echo " Done!"

	sleep 60
	echo -e "INFO: Resetting TESTOS password ...\c"
	testhost_reset_passwd
	echo " Done!"
	sleep 1
	echo -e "INFO: Verifying TESTOS ...\c"
	testhost_verify
	echo " Done!"
	sleep 10
	if [ ${testhost_install_only} -eq 1 ]; then
		echo "INFO: Install finished, change password successful! user/passwd: root/qwerasdf1234"
		keep_test_machine 'unlock'
		exit 0
	fi
	sleep 50

	# run script
	echo -e "INFO: Starting to run test case ${HOSTAlias}/${CASEPolarionID} ...\c"
	[ ! -x ${CASERunScript} ] && chmod a+x ${CASERunScript}
	./${CASERunScript}
	caserun_exit=$?
	if [ ${caserun_exit} -eq 0 ]; then
		echo " PASS!"
		mail_title="${HOSTAlias}_${CASEPolarionID}_PASS"
	else
		echo " FAIL!"
		mail_title="${HOSTAlias}_${CASEPolarionID}_FAIL"
	fi
	
	echo -e "INFO: Saving log ...\c"
	cd /tmp/
	tar zcf ${CASEPolarionID}.tar.gz `basename ${TESTCASELOG}`
	cd - > /dev/null
	echo " Done!"
	echo -e "INFO: Sending mail to ${MAILTO} ...\c"
	cd ${TESTCASELOG}
	cat ${TESTCASELOG}/${CASEPolarionID}.output | mail -s ${mail_title} -r `hostname | awk -F'.' '{print $1}'`@xxx.com -a /tmp/${CASEPolarionID}.tar.gz ${MAILTO}
	cd - > /dev/null
	echo " Done!"
	rm -rf /tmp/{CASEPolarionID}.tar.gz
	rm -rf ${TESTCASELOG}/*
	echo -e "INFO: Finished ${HOSTAlias}/${CASEPolarionID} testing, no errors detect, testing ...\c"
	if [ ${caserun_exit} -eq 0 ]; then
		echo " PASS!"
	else
		echo " FAIL!"
	fi
	echo "----------------------------Finishing ${CASEPolarionID}-----------------------------------"
	echo
	echo
	echo
	(( lincase = lincase + 1))
	sleep 90
done
echo -e "INFO: Unlocking the test server ...\c"
keep_test_machine 'unlock'
echo " Done!"
echo "----------------------------Testing end on ${HOSTAlias}------------------------------------"
