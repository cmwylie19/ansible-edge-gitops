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
    - name: Retrieve API hostname for AAP
      kubernetes.core.k8s_info:
        kind: Route
        namespace: ansible-automation-platform
        name: controller
      register: aap_host
      failed_when: aap_host.resources | length == 0

    - name: Set ansible_host
      set_fact:
        ansible_host: '{{ aap_host.resources[0].spec.host }}'

    - name: Retrieve admin password for AAP
      kubernetes.core.k8s_info:
        kind: Secret
        namespace: ansible-automation-platform
        name: controller-admin-password
      register: admin_pw
      failed_when: admin_pw.resources | length == 0

    - name: Set admin_password fact
      set_fact:
        admin_password: '{{ admin_pw.resources[0].data.password | b64decode }}'

    - name: Report AAP Endpoint
      debug:
        msg: 'AAP Endpoint: https://{{ ansible_host }}'

    - name: Report AAP User
      debug:
        msg: 'AAP Admin User: admin'

    - name: Report AAP Admin Password
      debug:
        msg: 'AAP Admin Password: {{ admin_password }}'
