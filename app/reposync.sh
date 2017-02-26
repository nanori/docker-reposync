#!/bin/bash
if [ "${DEBUG}" == "true" ]; then 
	LOG_LEVEL=2
	set -x
fi

#############
# Variables #
#############
export LOCALREPO_LOCATION=${LOCALREPO_LOCATION:-/tmp/repos}
export TEMP_DIR=${TEMP_DIR:-/tmp}
export REPOSYNC_DEFAULT_FLAGS=${REPOSYNC_DEFAULT_FLAGS:-"-n -d -l"}
export LOG_LEVEL=${LOG_LEVEL:-0}

#############
# Functions #
#############
function f_repo_sync_yum {
	repo=$1
	repomirror=$2
	download_path=$3

	repofile=${TEMP_DIR}/${repo}.repo

	echo "INFO  | Starting reposync for repoid '${repo}' to '${download_path} using reposync"
	echo "DEBUG | Creating repofile '$repofile'"
	cat << EOF > $repofile
[$repo]
baseurl=$repomirror
enabled=1
gpgcheck=0
EOF
	echo "DEBUG | Run reposync command"
	# --cachedir mandatory to avoid 'Error: Could not make cachedir, exiting' with random uid
	reposync --repoid $repo \
		--download_path $download_path \
		--norepopath \
		--config=$repofile \
		--arch x86_64 \
		--cachedir /tmp/yum/cache \
		${REPOSYNC_DEFAULT_FLAGS}
}

function f_repo_sync_wget {
   repo=$1
   repomirror=$2
   download_path=$3
   echo "INFO  | Starting reposync for repoid '${repo}' to '${download_path} using wget"
   # -N  : Turn on time-stamping
   # -np : Do not ever ascend to the parent directory when retrieving recursively
   # -r  : Turn on recursive retrieving.
   # -l  : depth 
   # -nd : Do not create a hierarchy of directories when retrieving recursively
   # -P  : Downdload dir
   wget -N -np -r -l inf -nd --progress=bar:force -P $download_path $repomirror
}

function f_print_output {
	level=$1
	msg=$2
	case "$1" in
		ERROR)
			level_num=0
			;;
		INFO)
			level_num=1
			;;
		DEBUG)
			level_num=2
			;;
	esac
	if [ $level_num -le $LOG_LEVEL ]; then
		printf "%-7s | %s\n" "$level" "$msg"
	fi
}

########
# MAIN #
########
repo_errors=0

while true; do
  case "$1" in
    -r | --repomirror ) 
      repomirror="$2"; shift 2 ;;
    -n | --repoid ) 
      repo="$2"; shift 2 ;;
    -d | --download-path ) 
      download_path="$2"; shift 2 ;;
    -b | --breed )
      breed="$2"; shift 2 ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

download_path=${LOCALREPO_LOCATION}/${relative_download_path}

case "$breed" in
   yum )
      f_repo_sync_yum $repo $repomirror $download_path
      rc_reposync=$?
      if [ $rc_reposync -eq 0 ]; then
         f_print_output "INFO" "Starting create repo for repoid '${repo}'"
         createrepo --update $download_path
      else
         f_print_output "ERROR" "Reposync didn't end correctly. Abbording"
         repo_errors=$(( repo_errors + 1 ))
      fi
      ;;
   wget )
      f_repo_sync_wget $repo $repomirror $download_path
      ;;
esac

f_print_output "INFO" "Chanching mod of downloaded files"
chmod 775 -R $download_path
f_print_output "INFO"  "All repo synchronized. Repositories in error : $repo_errors"
