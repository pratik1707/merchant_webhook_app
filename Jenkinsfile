pipeline {
  agent any

  environment {
    RAILS_ENV    = 'test'
    DATABASE_URL = 'postgres://postgres:postgres@localhost:5432/merchant_webhook_app_test'
  }

  stages {
    stage('Install') {
      steps {
        sh 'bundle install'
      }
    }

    stage('Lint') {
      steps {
        sh 'bin/rubocop'
      }
    }

    stage('Test') {
      steps {
        sh 'bin/rails db:test:prepare'
        sh 'bin/rails test'
      }
    }
  }
}
