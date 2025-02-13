#!/usr/bin/env ansible-playbook
---
- name: "Install manifest on AAP controller"
  become: false
  connection: local
  hosts: localhost
  gather_facts: false
  vars:
    kubeconfig: "{{ lookup('env', 'KUBECONFIG') }}"
  tasks:
    - name: Fetch infrastructure values
      kubernetes.core.k8s_info:
        kind: Infrastructure
        namespace: ''
        name: cluster
      register: infra_values

# Do platform specific set facts here

    - name: Check for metal machinesets
      kubernetes.core.k8s_info:
        api: "machine.openshift.io/v1beta1"
        kind: MachineSet
        namespace: openshift-machine-api
      register: metal_machinesets

    - name: Display metal machinesets
      ansible.builtin.debug:
        msg: '{{ metal_machinesets }}'

    - name: "End play early if found"
      meta: end_play
      when: metal_machinesets.resources | length > 0

    - name: "End play"
      meta: end_play

    - name: Display infrastructure values
      ansible.builtin.debug:
        msg: '{{ infra_values }}'

    - name: Fetch machinesets
      kubernetes.core.k8s_info:
        api: "machine.openshift.io/v1beta1"
        kind: MachineSet
        namespace: openshift-machine-api
      register: machine_sets

    - name: Display machineset values
      ansible.builtin.debug:
        msg: '{{ machine_sets.resources[0] }}'

    - name: Copy machineset values
      ansible.builtin.copy:
        content: '{{ machine_sets.resources[0] | to_nice_yaml }}'
        dest: /tmp/ms1.yaml
