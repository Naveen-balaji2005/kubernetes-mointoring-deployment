pipeline {

    agent any

    stages {


        stage('terraform') {
            steps {
                sh 'terraform init'
                sh 'terraform plan'
                sh 'terraform apply -auto-approve'
                sh 'terraform destroy -auto-approve'     
            }
        }

    }
}
