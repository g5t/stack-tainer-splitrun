#!/bin/sh
#
# Orchestrate the communication between McStas and the ECDC stack
#
# Service              | Container             | Command
# ---------------------|-----------------------|---------
# Kakfa                | stack-tainer-kafka    | start-kafka (later, stop-kafka)
# Event Formation Unit | stack-tainer-splitrun | ${insrument} --calib ...
# Kafka-to-nexus       | stack-tainer-splitrun | launch-filewriter [this command]
# Forwarder            | stack-tainer-splitrun | launch-forwarder
# EPICS                | stack-tainer-splitrun | mp-epics
# mcstas-EPICS         | 
# mcstas-Readout       | 
#

# Allow this bash script to use job controls:
set -m -o errexit -o noclobber -o nounset

# (Maybe bad) specialize this script to work under BusyBox where bash is not available
# getopt exists but has slightly different syntax

# {option}: == one required argument
OPTIONS=broker:,work:,prefix:,command:,job:,help:
SHORT_OPTIONS=b:,w:,c:,j:,h:
PARSED=$(getopt -o $SHORT_OPTIONS -l $OPTIONS -- "$@") || exit 1
eval set -- "$PARSED"

[ -z ${BROKER+x} ] && broker="localhost:9092" || broker="${BROKER}"
[ -z ${WORK_DIR+x} ] && work_dir="$(pwd)" || work_dir="${WORK_DIR}"
[ -z ${WRITER_COMMAND+x} ] && writer_command="WriterCommand" || writer_command="${WRITER_COMMAND}"
[ -z ${WRITER_JOB+x} ] && writer_job="WriterJob" || writer_job="${WRITER_JOB}"
while true; do
  case "$1" in
    -b|--broker) broker="$2"; shift 2 ;;
    -w|--work) work_dir="$2"; shift 2 ;;
    -c|--command) writer_command="$2"; shift 2 ;;
    -j|--job) writer_job="$2"; shift 2 ;;
    -h|--help)
      echo "usage: $0 [options]"
      echo "options:"
      echo "  -h --help     print this help and exit"
      echo "  -b --broker   Kafka broker in {hostname}:{port} format, default='localhost:9092'"
      echo "  -w --work     The working directory to use for output file(s), default=\$PWD"
      echo "  -c --command  writer command topic, default='WriterCommand'"
      echo "  -j --job      writer job topic, default='WriterJob'"
      exit
    --) shift; break ;;
    *) echo "Programming error"; exit 3 ;;
  esac
done

if [ ! -d "${work_dir}" ]; then
  echo "The requested working directory ${work_dir} does not exist, creating it"
  mkdir -p "${work_dir}"
  if [ ! -d "${work_dir}" ]; then
    echo "Error creating working directory"
    exit 1
  fi
fi

# Register the *required to be predefined* Kafka topics (others can be defined on the fly later)
mp-register-topics --broker "${broker}" "${writer_command}" "${writer_job}"

# Get the list of known writers, just for logging purposes -- the two URIs are required even though they are not used
kafka-to-nexus --list_modules --command-status-uri "${broker}/${writer_command}" --job-pool-uri "${broker}/${writer_job}"
# Start a file writer
kafka-to-nexus --command-status-uri "${broker}/${writer_command}" \
               --job-pool-uri "${broker}/${writer_job}" \
               --hdf-output-prefix="${work_dir}/"\
               --verbosity trace \
               --kafka-error-timeout 10s\
               --kafka-poll-timeout 1s\
               --kafka-metadata-max-timeout 10s
               #--kafka-config consumer.timeout.ms 20000

