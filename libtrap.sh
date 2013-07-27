#!/bin/bash
# From: http://stackoverflow.com/questions/3338030/multiple-bash-traps-for-the-same-signal
# Licensed under http://creativecommons.org/licenses/by-sa/2.5/
trap_stack_name() {
  local sig=${1//[^a-zA-Z0-9]/_}
  echo "__trap_stack_$sig"
}

extract_trap() {
  echo ${@:3:$(($#-3))}
}

get_trap() {
  eval echo $(extract_trap `trap -p $1`)
}

trap_push() {
  local new_trap=$1
  shift
  local sigs=$*
  for sig in $sigs; do
    local stack_name=`trap_stack_name "$sig"`
    local old_trap=$(get_trap $sig)
    eval "${stack_name}"'[${#'"${stack_name}"'[@]}]=$old_trap'
    trap "${new_trap}" "$sig"
  done
}

trap_pop() {
  local sigs=$*
  for sig in $sigs; do
    local stack_name=`trap_stack_name "$sig"`
    local count; eval 'count=${#'"${stack_name}"'[@]}'
    [[ $count -lt 1 ]] && return 127
    local new_trap
    local ref="${stack_name}"'[${#'"${stack_name}"'[@]}-1]'
    local cmd='new_trap=${'"$ref}"; eval $cmd
    trap "${new_trap}" "$sig"
    eval "unset $ref"
  done
}

trap_prepend() {
  local new_trap=$1
  shift
  local sigs=$*
  for sig in $sigs; do
    if [[ -z $(get_trap $sig) ]]; then
      trap_push "$new_trap" "$sig"
    else
      trap_push "$new_trap ; $(get_trap $sig)" "$sig"
    fi
  done
}

trap_append() {
  local new_trap=$1
  shift
  local sigs=$*
  for sig in $sigs; do
    if [[ -z $(get_trap $sig) ]]; then
      trap_push "$new_trap" "$sig"
    else
      trap_push "$(get_trap $sig) ; $new_trap" "$sig"
    fi
  done
}
