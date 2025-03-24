@Library("jenkins-library@main")

import com.logicalclocks.jenkins.k8s.ImageBuilder

properties([
  parameters([
    choice(name: 'image', choices: ['all', 'sklearnserver', 'kserve-controller'],  description: 'Which docker image to build'),
    choice(name: 'branch', choices: ['', 'release-0.11.2', 'release-0.14.0', 'release-0.14.1', 'release-0.14.1.1'],  description: 'Which branch to build'),
  ])
])

node("local") {
    stage('Clone repository') {
      if (params.branch == ''){
        checkout scm
      } else {
        sshagent (credentials: ['id_rsa']) {
          sh """
            git fetch --all
            git checkout ${params.branch}
            git pull
          """
        }
      }
    }

    stage('Build and push image(s)') {
        version = readFile "${env.WORKSPACE}/VERSION"
        withEnv(["VERSION=${version.trim()}"]) {
          
            if(params.image == 'all' || params.image == 'sklearnserver'){

                def builder = new ImageBuilder(this)
                m = readFile "${env.WORKSPACE}/python/sklearn-build-manifest.json"
                builder.run(m)
            }

            if(params.image == 'all' || params.image == 'kserve-controller'){

                def builder = new ImageBuilder(this)
                m = readFile "${env.WORKSPACE}/kserve-controller-build-manifest.json"
                builder.run(m)
            }
        }
    }
}