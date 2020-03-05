#!groovy

/*
 * Copyright (c) 2020, AT&T Intellectual Property.
 * All rights reserved.
 *
 * SPDX-License-Identifier: GPL-2.0-only
 */

// Pull Request builds might fail due to missing diffs: https://issues.jenkins-ci.org/browse/JENKINS-45997
// Pull Request builds relationship to their targets branch: https://issues.jenkins-ci.org/browse/JENKINS-37491

@NonCPS
def cancelPreviousBuilds() {
    def jobName = env.JOB_NAME
    def buildNumber = env.BUILD_NUMBER.toInteger()
    /* Get job name */
    def currentJob = Jenkins.instance.getItemByFullName(jobName)

    /* Iterating over the builds for specific job */
    for (def build : currentJob.builds) {
        /* If there is a build that is currently running and it's not current build */
        if (build.isBuilding() && build.number.toInteger() != buildNumber) {
            /* Than stopping it */
            build.doStop()
        }
    }
}

pipeline {
    agent any

    environment {
        OBS_TARGET_PROJECT = 'Vyatta:Master'
        OBS_TARGET_REPO = 'standard'
        OBS_TARGET_ARCH = 'x86_64'
        // # Replace : with _ in project name, as osc-buildpkg does
        OSC_BUILD_ROOT = "${WORKSPACE}" + '/build-root/' + "${env.OBS_TARGET_PROJECT.replace(':','_')}" + '-' + "${env.OBS_TARGET_REPO}" + '-' + "${OBS_TARGET_ARCH}"
        DH_VERBOSE = 1
        DH_QUIET = 0
        DEB_BUILD_OPTIONS ='verbose'
    }

    options {
        timeout(time: 180, unit: 'MINUTES') // Hopefully maximum even when Valgrind is included!
        checkoutToSubdirectory("vplane-config-npf")
        quietPeriod(30) // Wait in case there are more SCM pushes/PR merges coming
        ansiColor('xterm')
        timestamps()
    }

    stages {

        // A work around, until this feature is implemented: https://issues.jenkins-ci.org/browse/JENKINS-47503
        stage('Cancel older builds') { steps { script {
            cancelPreviousBuilds()
        }}}

        stage('OSC config') {
            steps {
                sh 'printenv'
                // Build scripts with tasks to perform in the chroot
                sh """
cat <<EOF > osc-buildpackage_buildscript_default
export BUILD_ID=\"${BUILD_ID}\"
export JENKINS_NODE_COOKIE=\"${JENKINS_NODE_COOKIE}\"
dpkg-buildpackage -jauto -us -uc -b
EOF
"""
            }
        }

        stage('Install dependencies') {
            steps {
                sh 'pip3 install flake8'
            }
        }

        // Workspace specific chroot location used instead of /var/tmp
        // Allows parallel builds between jobs, but not between stages in a single job
        // TODO: Enhance osc-buildpkg to support parallel builds from the same pkg_srcdir
        // TODO: probably by allowing it to accept a .conf file from a location other than pkg_srcdir

        stage('OSC Build') {
            steps {
                dir('vplane-config-npf') {
                    sh """
cat <<EOF > .osc-buildpackage.conf
OSC_BUILDPACKAGE_TMP=\"${WORKSPACE}\"
OSC_BUILDPACKAGE_BUILDSCRIPT=\"${WORKSPACE}/osc-buildpackage_buildscript_default\"
EOF
"""
                    sh "osc-buildpkg -v -g -T -P ${env.OBS_TARGET_PROJECT} ${env.OBS_TARGET_REPO} -- --trust-all-projects --build-uid='caller'"
                }
            }
        }

        stage('Code Stats') {
            when {expression { env.CHANGE_ID == null }} // Not when this is a Pull Request
            steps {
                sh 'sloccount --duplicates --wide --details vplane-config-npf > sloccount.sc'
                sloccountPublish pattern: '**/sloccount.sc'
            }
        }

/* We can't do a simple
 *    sh "dram --username jenkins -d yang"
 * because the base yang dir contains a VNF module
 * and there are platform modules in another dir.
 */
        stage('DRAM') {
            steps {
                dir('vplane-config-npf') {
                    sh '''
yang=`echo yang/*.yang | sed 's@yang/vyatta-policy-pbr-bridge-v1.yang @@' | sed 's/ /,/g'`
platform=`echo platform/*.platform | sed 's/ /,/g'`
platyang=`echo platform/*.yang | sed 's/ /,/g'`
dram --username jenkins -f \$yang -P \$platform -Y \$platyang -v yang/vyatta-policy-pbr-bridge-v1.yang
'''
                }
            }
        }

        stage('Perlcritic') {
            steps {
                dir('vplane-config-npf') {
                    sh script: "perlcritic --quiet --severity 5 . 2>&1 | tee perlcritic.txt", returnStatus: true
                }
            }
        }

        stage('Flake8') {
            steps {
                dir('vplane-config-npf') {
                    sh '''
pyfiles=`find . -exec file {} \\; | grep -i python | cut -d: -f1 | cut -c3- | xargs`
python3 -m flake8 --output-file=flake8.out --count --exit-zero --exclude=.git/*,debian/* \$pyfiles
'''
                }
            }
        }
    } // stages

    post {
        always {
            sh 'rm -f *.deb' // top-level dir
            // Re-enable these once the osc wipe is fixed.
            //sh "osc chroot --wipe --force --root ${env.OSC_BUILD_ROOT}"
            //deleteDir()

            recordIssues tool: perlCritic(pattern: 'vplane-config-npf/perlcritic.txt'),
                qualityGates: [[type: 'TOTAL', threshold: 1, unstable: true]]

            recordIssues tool: flake8(pattern: 'vplane-config-npf/flake8.out'),
                qualityGates: [[type: 'TOTAL', threshold: 69, unstable: true]]

            // Do any clean up for DRAM?
        }
        success {
            echo 'Winning'
        }
        failure {
            echo 'Argh... something went wrong'
            emailext (
                subject: "FAILED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
                body: """<p>FAILED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]':</p>
                         <p>Check console output at "<a href="${env.BUILD_URL}">${env.JOB_NAME} [${env.BUILD_NUMBER}]</a>"</p>""",
                recipientProviders: [culprits()]
            )
        }
    }
}
