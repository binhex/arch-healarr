#!/usr/bin/dumb-init /bin/bash

# Script to monitor defined containers for a health status of 'unhealthy' and perform a defined action

# script name and version
ourScriptName=$(basename -- "$0")
ourFriendlyScriptName="${ourScriptName%.*}"

# source in utils (logging)
source utils.sh

# trap SIGTERM and SIGINT for graceful shutdown
trap 'shlog 1 "Received shutdown signal, exiting..."; exit 0' SIGTERM SIGINT

function pre_reqs() {

	if ! command -v docker &> /dev/null; then
		shlog 3 "Docker CLI not found, exiting script..."
		exit 1
	fi

	# check if docker socket is accessible
	if ! docker ps &> /dev/null; then
		shlog 3 "Cannot communicate with Docker daemon, check socket is mounted at /var/run/docker.sock"
		exit 1
	fi

	if ! command -v apprise &> /dev/null; then
		shlog 3 "Apprise CLI not found, exiting script..."
		exit 1
	fi

	shlog 1 "Docker CLI and Apprise CLI found and accessible"

}

function env_vars() {

	if [[ -z "${MONITOR_INTERVAL}" ]]; then
		export MONITOR_INTERVAL=60
		shlog 2 "MONITOR_INTERVAL not defined, defaulting to '${MONITOR_INTERVAL}' seconds"
	fi

	if [[ -z "${RETRY_COUNT}" ]]; then
		export RETRY_COUNT=3
		shlog 2 "RETRY_COUNT not defined, defaulting to '${RETRY_COUNT}'"
	fi

	if [[ -z "${RETRY_DELAY}" ]]; then
		export RETRY_DELAY=10
		shlog 2 "RETRY_DELAY not defined, defaulting to '${RETRY_DELAY}' seconds"
	fi

	if [[ -z "${ACTION}" ]]; then
		export ACTION="restart"
		shlog 2 "ACTION not defined, defaulting to '${ACTION}'"
	fi

	if [[ -n "${APPRISE_NOTIFICATION_SERVICES}" ]]; then
		shlog 1 "Apprise notifications enabled for services: ${APPRISE_NOTIFICATION_SERVICES}"
	fi

	# log filter configuration
	local filter_count=0

	if [[ -n "${CONTAINER_LABEL}" ]]; then
		shlog 1 "Filtering containers by label: ${CONTAINER_LABEL}"
		((filter_count++))
	fi

	if [[ -n "${CONTAINER_ENV_VAR}" ]]; then
		shlog 1 "Filtering containers by environment variable: ${CONTAINER_ENV_VAR}"
		((filter_count++))
	fi

	if [[ -n "${CONTAINER_NAME}" ]]; then
		shlog 1 "Filtering containers by name(s): ${CONTAINER_NAME}"
		((filter_count++))
	fi

	if [[ ${filter_count} -eq 0 ]]; then
		shlog 1 "No filters specified, monitoring all containers with healthchecks"
	fi

}

function filter_containers() {

	local all_containers="${1}"
  shift

	local unhealthy_containers

	# if any filters are defined, we need to check each container
	if [[ -n "${CONTAINER_LABEL}" || -n "${CONTAINER_ENV_VAR}" || -n "${CONTAINER_NAME}" ]]; then

		while IFS= read -r container; do
			local match=false

			# check label filter
			if [[ -n "${CONTAINER_LABEL}" ]]; then
				if docker inspect --format "{{.Config.Labels}}" "${container}" 2>/dev/null | grep -q "${CONTAINER_LABEL}"; then
					match=true
				fi
			fi

			# check env var filter
			if [[ -n "${CONTAINER_ENV_VAR}" && "${match}" != "true" ]]; then
				if docker inspect --format "{{.Config.Env}}" "${container}" 2>/dev/null | grep -q "${CONTAINER_ENV_VAR}"; then
					match=true
				fi
			fi

			# check name filter (comma-separated list)
			if [[ -n "${CONTAINER_NAME}" && "${match}" != "true" ]]; then
				IFS=',' read -ra names <<< "${CONTAINER_NAME}"
				for name in "${names[@]}"; do
					# trim whitespace
					name=$(echo "${name}" | xargs)
					if [[ "${container}" == "${name}" ]]; then
						match=true
						break
					fi
				done
			fi

			# add to filtered list if matched
			if [[ "${match}" == "true" ]]; then
				if [[ -z "${unhealthy_containers}" ]]; then
					unhealthy_containers="${container}"
				else
					unhealthy_containers="${unhealthy_containers}"$'\n'"${container}"
				fi
			fi
		done <<< "${all_containers}"
	else
		# no filters, use all unhealthy containers
		unhealthy_containers="${all_containers}"
	fi

	# create global variable for unhealthy containers after filtering
	UNHEALTHY_CONTAINERS="${unhealthy_containers}"

}

function apprise_notifications() {

	local container_name="${1}"
	shift
	local action_status="${1}"
	shift

	if [[ -n "${APPRISE_NOTIFICATION_SERVICES}" ]]; then
		local message="[${ourFriendlyScriptName}] Container '${container_name}' was unhealthy. Action '${ACTION}' (${action_status})."

		# convert comma-separated list to space-separated for apprise
		local services
		IFS=',' read -ra service_array <<< "${APPRISE_NOTIFICATION_SERVICES}"
		for service in "${service_array[@]}"; do
			# trim whitespace
			service=$(echo "${service}" | xargs)
			if [[ -z "${services}" ]]; then
				services="${service}"
			else
				services="${services} ${service}"
			fi
		done

		if apprise \
			-vv \
			-t "[${ourFriendlyScriptName}] Container Unhealthy" \
			-b "${message}" \
			${services}; then
			shlog 1 "Notification sent for container '${container_name}'"
		else
			shlog 2 "Failed to send notification for container '${container_name}'"
		fi
	fi

}

function process_unhealthy_container() {

	local container_name="${1}"
  shift

	shlog 2 "Container '${container_name}' is unhealthy. Checking health status with retries..."

	# retry health check before taking action
	local attempt=1
	local still_unhealthy=true

	while [[ ${attempt} -le ${RETRY_COUNT} ]]; do
		shlog 1 "Health check attempt ${attempt}/${RETRY_COUNT} for container '${container_name}'..."

		local health_status
		health_status=$(docker inspect --format='{{.State.Health.Status}}' "${container_name}" 2>/dev/null)

		if [[ "${health_status,,}" == "healthy" ]]; then
			shlog 1 "Container '${container_name}' is now healthy, no action needed"
			still_unhealthy=false
			break
		else
			shlog 2 "Container '${container_name}' health status: ${health_status}"

			if [[ ${attempt} -lt ${RETRY_COUNT} ]]; then
				shlog 1 "Waiting ${RETRY_DELAY} seconds before next health check..."
				sleep "${RETRY_DELAY}"
			fi
		fi

		((attempt++))
	done

	# if still unhealthy after all retries, execute action
	if [[ "${still_unhealthy}" == "true" ]]; then
		shlog 2 "Container '${container_name}' still unhealthy after ${RETRY_COUNT} checks. Executing action '${ACTION}'..."

		if docker "${ACTION}" "${container_name}" &>/dev/null; then
			shlog 1 "Successfully executed action '${ACTION}' on container '${container_name}'"
			apprise_notifications "${container_name}" "SUCCESS"
		else
			shlog 3 "Failed to execute action '${ACTION}' on container '${container_name}'"
			apprise_notifications "${container_name}" "FAILED"
		fi
	fi

}

function process_containers() {

	shlog 1 "Starting ${ourFriendlyScriptName} (interval: ${MONITOR_INTERVAL} seconds)..."

	while true; do
		local all_containers

		# get all unhealthy containers first
		all_containers=$(docker ps --filter "health=unhealthy" --format "{{.Names}}")

		# apply filters if specified
		if [[ -n "${all_containers}" ]]; then
			filter_containers "${all_containers}"
		else
			# clear the global variable if no unhealthy containers found
			UNHEALTHY_CONTAINERS=""
		fi

		if [[ -z "${UNHEALTHY_CONTAINERS}" ]]; then
			shlog 1 "No unhealthy containers found"
		else
			echo "${UNHEALTHY_CONTAINERS}" | while read -r container_name; do
				if [[ -n "${container_name}" ]]; then
					process_unhealthy_container "${container_name}"
				fi
			done
		fi

		shlog 1 "Sleeping for ${MONITOR_INTERVAL} seconds before next check..."
		sleep "${MONITOR_INTERVAL}" &
		wait $!  # wait for sleep to finish, allows trap to interrupt
	done

}

function main() {

	# check prerequisites
	pre_reqs

	# process env_vars
	env_vars

	# run continuous health check loop
	process_containers

}

# run function to start processing
main