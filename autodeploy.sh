#!/usr/bin/env bash
set +x
: <<EOF
Written by m2nlight

return value:
1 - parse command line arguments error
2 - other error
EOF

read -r -d '' my_title <<-EOF
	=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
	|    autodeploy.sh v2020.1.19     |
	=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
EOF

read -r -d '' my_usage <<-EOF
	Usage
		bash $(basename "$0") [options]

	Options
		-h, --help            show helpful information
		-c, --crontab         no output to tty
		-r, --repo            a git repo local directory
		                      for check remote repo update
		-f, --find-commit     find COMMIT_ID in logfile

		-m, --mail            use mailx command to send email when job finish
		                      ex: --mail alice@domain.com,bob@domain.com
		                      how to install mailx:
		                      redhat: yum install mailx
		                      debian: apt-get install mailutils
		    --cc              copies to list of email addresses
		-s, --subject         email subject
		-a, --append-logfile  the logfile as email attachment
		    --from            email from
		    --test-mail       just test mail, no deloy
EOF

function show_usage() {
	cat <<-EOF
		$my_title
		This is a bash script for call deploy.sh

		You can run crontab -e to add a task like this:
		*/1  *  *  *  * path/to/autodeploy.sh -c -r path/to/repo -m alice@domain.com --cc bob@domain.com -a
		Let it can be automatic run every minute.
		You can run crontab -l to view tasks.
		If you have a mail, you can run follow command
		cat /var/mail/$USER   # show your mail context.
		mailq                 # show mail queue
		sudo postsuper -d ID  # remove a mail from queue (postfix)
		sudo postfix flush    # flush mails
		vim ~/.mailrc         # edit mail config
			set smtp-use-starttls
			set ssl-verify=ignore
			set smtp=smtp://smtp.gmail.com:587
			set smtp-auth=login
			set smtp-auth-user=YOURNAME@gmail.com
			set smtp-auth-password="XXXX XXXX XXXX XXXX"
			set from="YOURNAME <YOURNAME@gmail.com>"
			set nss-config-dir=/etc/pki/nssdb
		chmod 600 ~/.mailrc   # for security
		sudo find / -name "cert*.db"  # find nss-config-dir

		You must have named deploy.sh file in same path.
		This script will call it and with a race condition
		by /var/tmp/autodeploy.sh.lock file, run
		cat /var/tmp/autodeploy.sh.lock to view the PID.

		A git repo local directory is optional.
		It will be check for whether create the log file.

		The log filename is autodeploy.log, or
		when with --repo will be autodeploy.\$COMMIT_ID.log

		$my_usage

	EOF
}

my_source_dir="$(dirname "${BASH_SOURCE[0]}")"
my_lockfile='/var/tmp/autodeploy.sh.lock'
my_log="${my_source_dir}/autodeploy.log"
my_allow_logfile=1
my_flag_crontab=0
my_flag_repo=''
my_flag_mail=''
my_flag_cc=''
my_flag_subject=''
my_flag_from=''
my_flag_appendlogfile=0
my_flag_testmail=0
until [ $# -eq 0 ]; do
	case "$1" in
	-h | --help)
		show_usage
		exit 0
		;;
	-c | --crontab)
		my_flag_crontab=1
		;;
	-r | --repo)
		shift
		if [ ! -d "$1" ]; then
			echo 'ERROR: --repo argument error, need a git repo directory'
			exit 1
		fi
		my_flag_repo="$1"
		my_allow_logfile=0
		;;
	-m | --mail)
		shift
		if [ -z "$1" ]; then
			echo 'ERROR: --mail argument error, need some email addresses'
			exit 1
		fi
		my_flag_mail="$1"
		;;
	--cc)
		shift
		if [ -z "$1" ]; then
			echo 'ERROR: --cc argument error, need some email addresses'
			exit 1
		fi
		my_flag_cc="$1"
		;;
	-s,--subject)
		shift
		if [ -z "$1" ]; then
			echo 'ERROR: --subject argument error, need email subject'
			exit 1
		fi
		my_flag_subject="$1"
		;;
	-a | --append-logfile)
		my_flag_appendlogfile=1
		;;
	--from)
		shift
		if [ -z "$1" ]; then
			echo 'ERROR: --from argument error, need email from string'
			exit 1
		fi
		my_flag_from="$1"
		;;
	--test-mail)
		my_flag_testmail=1
		;;
	-f | --find-commit)
		shift
		if [ ! -f "$1" ]; then
			echo 'ERROR: --find-commit argument error, need a log filename'
			exit 1
		fi
		grep -oP -m1 '(?<=COMMIT_ID: ).*' "$1"
		exit 0
		;;
	*)
		echo -e "ERROR: arguments error\nplease run \"bash ${0##*/} --help\" to get usage"
		exit 1
		;;
	esac
	shift
done

function curtime() {
	# TZ=UTC-8 will show beijing time
	TZ=UTC-8 date +"%Y-%m-%d-%a-%H-%M-%S"
}

function do_cmd() {
	local my_ret=0
	if [ $my_flag_crontab -eq 0 ]; then
		if [ $my_allow_logfile -ne 0 ]; then
			# output to tty and logfile
			"$@" | tee -a "$my_log"
			my_ret=$?
		else
			# output to tty only
			"$@"
			my_ret=$?
		fi
	else
		if [ $my_allow_logfile -ne 0 ]; then
			# output to logfile only
			"$@" >>"$my_log" 2>&1
			my_ret=$?
		else
			# no output
			"$@" &>/dev/null
			my_ret=$?
		fi
	fi
	return $my_ret
}

function log() {
	if [ "$1" == "-e" ]; then
		shift
		do_cmd echo -e "$(curtime) $*"
	else
		do_cmd echo "$(curtime) $*"
	fi
}

function log_title() {
	do_cmd echo "$my_title"
	log "USER: $USER  PWD: $PWD  LOCKFILE: $my_lockfile"
}

function send_mail() {
	[ -z "$my_flag_mail" ] && return 0
	command -v mailx &>/dev/null || return 0

	local -a my_mail_args
	if [ $my_flag_testmail -eq 1 ]; then
		my_mail_args+=(-v)
	fi

	if [ -z "$my_flag_subject" ]; then
		my_flag_subject="autodeploy result @$(curtime)"
	fi
	my_mail_args+=(-s "$my_flag_subject")

	if [ ! -z "$my_flag_cc" ]; then
		my_mail_args+=(-c "$my_flag_cc")
	fi

	if [ -z "$my_flag_from" ] && [ -f "$HOME/.mailrc" ]; then
		local my_email="$(grep -o -m1 '[[:alnum:]]\+@[[:alnum:]]\+' "$HOME/.mailrc")"
		if [ ! -z "$my_email" ]; then
			my_flag_from="AutoDeploy <$my_email>"
		fi
	fi
	if [ ! -z "$my_flag_from" ]; then
		my_mail_args+=(-r "$my_flag_from")
	fi

	if [ $my_flag_appendlogfile -eq 1 ]; then
		my_mail_args+=(-a "$my_log")
	fi

	my_mail_args+=("$my_flag_mail")
	echo "$*" | do_cmd mailx "${my_mail_args[@]}"
}

# deploy code in this function
function deploy() {
	if [ $my_flag_testmail -eq 1 ]; then
		send_mail "test mail"
		exit 0
	fi
	# goto the autodeploy directory
	local my_deploy='deploy.sh'
	pushd "$my_source_dir" &>/dev/null
	log_title

	# deploy stuff here
	if [ ! -f "$my_deploy" ]; then
		log "ERROR: file not exists: $my_deploy"
		exit 2
	fi
	# check git repo and update current branch
	if [ ! -z "$my_flag_repo" ]; then
		pushd "$my_flag_repo" &>/dev/null
		log "REPO: $my_flag_repo"
		local my_git_remotebranch=$(git rev-parse --abbrev-ref --symbolic-full-name @{u})
		if [ -z "$my_git_remotebranch" ]; then
			log "WARNNING: can't get remote branch name, ignroe check repo"
		else
			local my_git_remote="${my_git_remotebranch%%/*}"
			local my_git_rb="${my_git_remotebranch#*/}"
			local my_git_commit="$(git rev-parse HEAD)"
			do_cmd git fetch $my_git_remote $my_git_rb
			local my_git_fetch_commit="$(git rev-parse FETCH_HEAD)"
			if [ "$my_git_commit" == "$my_git_fetch_commit" ]; then
				# note: 'COMMIT_ID: ' is a keyword for call with --find-commit
				log "No update, COMMIT_ID: $(git rev-parse --short HEAD)"
				exit 0
			fi

			local my_git_commit_short="$(git rev-parse --short $my_git_fetch_commit)"
			my_allow_logfile=1
			if [ ! -z "$my_git_commit_short" ]; then
				my_log="${my_log%.*}.${my_git_commit_short}.log"
			fi
			log_title
			log -e "REPO: $my_flag_repo\nRemote: $(git remote -v)\nRemote branch: $my_git_remotebranch\nFETCH_HEAD: $my_git_fetch_commit\nHEAD: $my_git_commit\n"
			log "git clean..."
			do_cmd git clean -xdf
			log "git reset to FETCH_HEAD ..."
			do_cmd git reset --hard $my_git_fetch_commit
			# note: 'COMMIT_ID: ' is a keyword for call with --find-commit
			log "COMMIT_ID: $my_git_commit_short"
		fi
		popd &>/dev/null
	fi
	# call deploy.sh
	local my_deploy_start=$(date +%s)
	set -e
	do_cmd sh "$my_deploy"
	local my_ret=$?
	local my_deploy_cost=$(($(date +%s) - $my_deploy_start))
	local my_result=''
	if [ $my_ret -eq 0 ]; then
		result="RESULT: SUCCESS  COST: ${my_deploy_cost}s"
	else
		result="RESULT: FAILURE $my_ret  COST: ${my_deploy_cost}s"
	fi
	log $result
	send_mail "$result  LOGFILE: $my_log"
	set +e
	popd &>/dev/null
}

# correct lock and entry
# if shell is ksh88, use mkdir $lockdir instead of the condition
# see: https://unix.stackexchange.com/questions/22044/correct-locking-in-shell-scripts
if (
	set -o noclobber
	echo "$$" >"$my_lockfile"
) 2>/dev/null; then
	trap 'rm -f "$my_lockfile"; exit $?' INT TERM EXIT
	deploy
	rm -f "$my_lockfile"
	trap - INT TERM EXIT
else
	log "lock exists: $my_lockfile owned by $(cat $my_lockfile)"
fi
