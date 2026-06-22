#!/bin/bash
# SafeCity — Jenkins Auto-Configuration
set -e

JENKINS_URL="http://localhost:8080"
echo "Waiting for Jenkins to be ready ..."
for i in $(seq 1 36); do
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$JENKINS_URL/login" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" != "000" ] && [ "$HTTP_CODE" != "503" ]; then
        echo "Jenkins is ready (HTTP $HTTP_CODE)."
        break
    fi
    sleep 10
done

JENKINS_PASS=$(docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword)
echo "Jenkins admin password obtained."

# Download CLI
curl -s "$JENKINS_URL/jnlpJars/jenkins-cli.jar" -o /tmp/jenkins-cli.jar

# Install plugins
echo "Installing Jenkins plugins ..."
java -jar /tmp/jenkins-cli.jar -auth "admin:$JENKINS_PASS" install-plugin \
    git pipeline-model-definition docker-workflow credentials-binding || true

echo "Waiting for plugins to finalize ..."
sleep 30

# Create the pipeline job
echo "Creating pipeline job ..."
cat > /tmp/safecity-job.xml << 'XML'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="pipeline-model-definition">
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>https://github.com/devdarshan1495/SafeCity.git</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/master</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
    </scm>
    <scriptPath>Jenkinsfile</scriptPath>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
XML

if java -jar /tmp/jenkins-cli.jar -auth "admin:$JENKINS_PASS" create-job safecity-pipeline < /tmp/safecity-job.xml 2>/dev/null; then
    echo "Pipeline job 'safecity-pipeline' created."
else
    java -jar /tmp/jenkins-cli.jar -auth "admin:$JENKINS_PASS" update-job safecity-pipeline < /tmp/safecity-job.xml 2>/dev/null || true
    echo "Pipeline job updated."
fi

# Set a known admin password for easy UI access
echo "Setting Jenkins admin password to 'safecity' ..."
java -jar /tmp/jenkins-cli.jar -auth "admin:$JENKINS_PASS" groovy = \
    'hudson.model.User.get("admin").setPassword("safecity")' 2>/dev/null || true

echo "Jenkins setup complete — login: admin / safecity"
