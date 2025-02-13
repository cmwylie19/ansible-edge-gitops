#!/usr/bin/env ansible-playbook
---
- name: "Install a metal worker"
  become: false
  connection: local
  hosts: localhost
  gather_facts: false
  vars:
    kubeconfig: "{{ lookup('env', 'KUBECONFIG') }}"
    machineset_blockdevices:
      - ebs:
          iops: 0
          volumeSize: 120
          volumeType: gp2
    machineset_instance_type: c5n.metal
    machineset_machine_role: worker
    machineset_machine_type: worker
    machineset_name: metal-worker
    machineset_node_labels:
      node-role.kubernetes.io/worker: ""
    machineset_replicas: 1
    machineset_user_data_secret: worker-user-data
  tasks:
    - name: Query Cluster Infrastructure Name
      community.kubernetes.k8s_info:
        api_version: config.openshift.io/v1
        kind: Infrastructure
        name: cluster
      register: cluster_info

    - name: Assert Platform is AWS
      ansible.builtin.assert:
        fail_msg: "Platform for OpenShift cluster must be AWS!"
        that:
          - cluster_info.resources[0].status.platform == "AWS"

    - name: Query MachineSets
      community.kubernetes.k8s_info:
        api_version: machine.openshift.io/v1beta1
        kind: MachineSet
        namespace: openshift-machine-api
      register: cluster_machinesets

    - name: Set Dynamic MachineSet Facts
      ansible.builtin.set_fact:
        machineset_ami_id: "{{ cluster_machinesets.resources[0].spec.template.spec.providerSpec.value.ami.id }}"
        machineset_subnet: "{{ cluster_machinesets.resources[0].spec.template.spec.providerSpec.value.subnet.filters[0]['values'][0] }}"
        machineset_tags: "{{ cluster_machinesets.resources[0].spec.template.spec.providerSpec.value.tags }}"
        machineset_zone: "{{ cluster_machinesets.resources[0].spec.template.spec.providerSpec.value.placement.availabilityZone }}"
        infrastructure_name: "{{ cluster_info.resources[0].status.infrastructureName }}"
        infrastructure_region: "{{ cluster_info.resources[0].status.platformStatus.aws.region }}"

    - name: Define template for creating machineset
      ansible.builtin.set_fact:
        machineset_yaml: |
          apiVersion: machine.openshift.io/v1beta1
          kind: MachineSet
          metadata:
            labels:
              machine.openshift.io/cluster-api-cluster: "{{ infrastructure_name }}"
            name: "{{ infrastructure_name }}-{{ machineset_name }}-{{ machineset_zone }}"
            namespace: openshift-machine-api
          spec:
            replicas: {{ machineset_replicas | int }}
            selector:
              matchLabels:
                machine.openshift.io/cluster-api-cluster: "{{ infrastructure_name }}"
                machine.openshift.io/cluster-api-machineset: "{{ infrastructure_name }}-{{ machineset_name }}-{{ machineset_zone }}"
            template:
              metadata:
                labels:
                  machine.openshift.io/cluster-api-cluster: "{{ infrastructure_name }}"
                  machine.openshift.io/cluster-api-machine-role: "{{ machineset_machine_role }}"
                  machine.openshift.io/cluster-api-machine-type: "{{ machineset_machine_type }}"
                  machine.openshift.io/cluster-api-machineset: "{{ infrastructure_name }}-{{ machineset_name }}-{{ machineset_zone }}"
          {% if machineset_os is defined %}
                  machine.openshift.io/os-id: {{ machineset_os }}
          {% endif %}
              spec:
                metadata:
                  labels: {{ machineset_node_labels }}
                providerSpec:
                  value:
                    ami:
                      id: "{{ machineset_ami_id }}"
                    apiVersion: awsproviderconfig.openshift.io/v1beta1
                    blockDevices: {{ machineset_blockdevices }}
                    credentialsSecret:
                      name: aws-cloud-credentials
                    deviceIndex: 0
                    iamInstanceProfile:
                      id: "{{ infrastructure_name }}-worker-profile"
                    instanceType: "{{ machineset_instance_type }}"
                    kind: AWSMachineProviderConfig
                    placement:
                      availabilityZone: "{{ machineset_zone }}"
                      region: "{{ infrastructure_region }}"
                    securityGroups:
                      - filters:
                          - name: tag:Name
                            values:
                              - "{{ infrastructure_name }}-worker-sg"
                    subnet:
                      filters:
                        - name: tag:Name
                          values:
                            - "{{ machineset_subnet }}"
                    tags: {{ machineset_tags }}
                    userDataSecret:
                      name: "{{ machineset_user_data_secret }}"
                      namespace: openshift-machine-api

    - name: Create MachineSet
      community.kubernetes.k8s:
        definition: "{{ machineset_yaml | from_yaml }}"
        state: present
