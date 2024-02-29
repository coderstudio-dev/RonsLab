terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
    }
    k8s = {
      source = "mingfang/k8s"
    }
  }
}

data "coder_workspace" "me" {}

variable "namespace" {}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  dir  = "/home/coder"
}

resource "k8s_core_v1_pod" "dev" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = "coder-${data.coder_workspace.me.owner}-${data.coder_workspace.me.name}"
    namespace = var.namespace
    annotations = {
      "io.kubernetes.cri-o.userns-mode" = "auto:size=65536"
    }
  }


  spec {

    # Use Sysbox container runtime (required)
    runtime_class_name = "sysbox-runc"

    # Run as root in order to start systemd (required)
    security_context {
      run_asuser = 0
      fsgroup    = 0
    }

    containers {
      name = "dev"
      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.main.token
      }
      image = "codercom/enterprise-base:ubuntu"
      command = ["sh", "-c", <<EOF
    # Start the Coder agent as the "coder" user
    # once systemd has started up
    sudo -u coder --preserve-env=CODER_AGENT_TOKEN /bin/bash -- <<-'    EOT' &
    while [[ ! $(systemctl is-system-running) =~ ^(running|degraded) ]]
    do
      echo "Waiting for system to start... $(systemctl is-system-running)"
      sleep 2
    done
    ${coder_agent.main.init_script}
    EOT

    exec /sbin/init
    EOF
      ]
    }
  }
}
