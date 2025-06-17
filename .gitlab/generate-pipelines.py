#!/usr/bin/env python3
# The script generates pipelines to be triggered basing on the content of the repository
# and changes in the current branch or commit

import os
import subprocess
import logging
from glob import glob
import yaml
from enum import Enum, auto


class ModuleType(Enum):
    Terragrunt = auto()
    Helmfile = auto()


def ci_job(env_name: str, module_name: str, cmd: str, cluster_name: str,
           module_type: ModuleType, manual: bool = False, stage: str = None, needs=None):
    """
    Returns a dict representing a Gitlab CI job and the name for the job
    """

    if module_type == ModuleType.Helmfile:
        tool = "helmfile"
        if cmd == "plan":
            cmd = "diff"
    elif module_type == ModuleType.Terragrunt:
        tool = "terragrunt"
    else:
        raise Exception(f"Unsupported module type '{module_type}' of module '{module_name}'")

    job = {
        'extends': f'.run-{tool}',
        'stage': stage or ('Apply' if cmd == 'apply' else 'Preview'),
        'tags': [f"{cluster_name}-cluster"],
        'variables': {
            'ENV_NAME': env_name,
            'MODULE_NAME': module_name,
            'CMD': cmd
        }
    }

    if manual:
        job['when'] = 'manual'

    if needs:
        job['needs'] = needs.copy()

    job_name = f'{(module_name or env_name).upper()} {tool} {cmd}'

    return job_name, job


def find_environments(directory):
    """
    Returns a list of tuples (path, name) of all environments in the given directory, recursively.
    """
    environments = []
    for root, dirs, files in os.walk(directory):
        if 'environment.yaml' in files:
            # If environment.yaml has already been found in a parent dir, issue a warning
            parent_envs = [e for e in environments if root.startswith(e)]
            if parent_envs:
                logging.warning(
                    f"Warning: Skipped {root}/environment.yaml as 'environment.yaml' found in parent directory {parent_envs[0]}.")
                continue
            environments.append(root)
    return [(e, str(os.path.relpath(e, directory))) for e in environments]


def find_modules(env_directory):
    """
    Returns a list of tuples (path, name, mtype) of Deploy Module found in the given directory
    """
    result = []
    for path in sorted(glob(os.path.join(env_directory, '*'))):
        if not os.path.isdir(path):
            continue
        if os.path.exists(os.path.join(path, "terragrunt.hcl")):
            mtype = ModuleType.Terragrunt
        elif os.path.exists(os.path.join(path, "helmfile.yaml")) or os.path.exists(os.path.join(path, "helmfile.yaml.gotmpl")):
            mtype = ModuleType.Helmfile
        else:
            raise Exception(f"Cannot determine deploy module type of '{path}'")
        result.append((path, os.path.basename(path), mtype))
    return result


def get_git_changes(path):
    """
    Seeks for changes made to the specified path[s] in the git repository.
    Compares to the default branch if we are not on the default branch or to the previous commit if we are
    on the default branch.

    Path could be given as a string or a list of strings

    Return a boolean value indicating whether any changes found.
    """
    if isinstance(path, str):
        path = [path]

    if CI_COMMIT_REF_NAME == CI_DEFAULT_BRANCH:
        changes = subprocess.check_output(
            ['git', 'diff', '--name-only', 'HEAD~1', '--'] + path).decode().strip()
    else:
        changes = subprocess.check_output(
            ['git', 'diff', '--name-only', f'HEAD..origin/{CI_DEFAULT_BRANCH}', '--'] + path).decode().strip()

    if changes:
        logging.debug(f"Found changes in [{','.join(path)}] : {changes}")

    return True if changes else False


def write_pipeline(file_name, pipeline):
    with open(file_name, 'w') as f:
        yaml.dump(pipeline, f, default_flow_style=False)
    logging.info(f"Generated file: {file_name}")


def main():
    # pipeline with environment trigger jobs
    the_pipeline = {
        'stages': ['Full Preview', 'Trigger'],
        "include": '.gitlab/jobs.yaml',
        "_generate-pipelines": {
            'stage': 'Trigger',
            'extends': '.generate-pipelines',
        }
    }

    on_default_branch = CI_COMMIT_REF_NAME == CI_DEFAULT_BRANCH

    # for every defined environment
    for env_path, env_name in find_environments(ENVIRONMENTS_DIR):

        logging.info(f"Found environment: {env_name}")

        # the environment pipeline
        env_pipeline_jobs = {}

        # load environment.yaml
        with open(os.path.join(env_path, 'environment.yaml'), 'r') as f:
            try:
                env_cfg = yaml.safe_load(f)
            except yaml.YAMLError as exc:
                print(exc)

        auto_apply_main = bool(env_cfg.get('ci', {}).get('auto_apply_main', False))
        branch_apply_enabled = bool(env_cfg.get('ci', {}).get('branch_apply_enabled', False))
        all_jobs_are_manual = bool(env_cfg.get('ci', {}).get('all_jobs_are_manual', False))
        cluster_name = env_cfg.get('cluster_name', "development")

        # Check if the env uses local template. If so, we will consider changes in the template
        # when detecting changes for a system
        tmpl_url = env_cfg.get('template', {}).get('url', '')
        if tmpl_url and not tmpl_url.startswith('ssh:') and not tmpl_url.startswith('https:'):
            # the env uses local template
            template_dir = tmpl_url #os.path.join(env_path, tmpl_url)
            logging.info(f"{env_name}: uses local template {template_dir}")
            if not os.path.isdir(template_dir):
                raise Exception(f"Template directory {template_dir} mentioned by env {env_path} does not exist.")
        else:
            # the env does not use local template or uses a remote template
            logging.info(f"{env_name}: Uses remote or none template")
            template_dir = None

        # check if there are any "global" changes that may probably affect any system
        helm_global_dependency_paths = \
            [os.path.join(env_path, 'environment.yaml')] + glob(os.path.join(template_dir, '*.yaml')) + glob(os.path.join(template_dir, '*.gotmpl'))

        tf_global_dependency_paths = \
            [os.path.join(env_path, 'environment.yaml')] + glob(os.path.join(CI_PROJECT_DIR, '*.hcl'))

        global_changes = {ModuleType.Helmfile: get_git_changes(helm_global_dependency_paths),
                          ModuleType.Terragrunt: get_git_changes(tf_global_dependency_paths)}
        if global_changes[ModuleType.Terragrunt]:
            logging.info(f"{env_name}: some env-global \033[91mchanges detected\033[0m affecting Terraform resources")
        if global_changes[ModuleType.Helmfile]:
            logging.info(f"{env_name}: some env-global \033[91mchanges detected\033[0m affecting Helm releases")

        env_changed = False
        prev_apply_jobs = []

        # create pipeline jobs for every deploy module
        for module_path, module_name, module_type in find_modules(env_path):

            preview_job_name, preview_job = None, None
            helm_preview_job_name, helm_preview_job = None, None

            # detect if there are any changes in the module
            module_changed = global_changes[module_type] or get_git_changes(module_path)
            if not module_changed and template_dir:
                module_changed = module_changed or get_git_changes(os.path.join(template_dir, module_name))

            if module_changed:
                logging.info(f"{env_name}: found deploy module {module_name}: \033[91mchanges detected\033[0m")
            else:
                logging.info(f"{env_name}: found deploy module {module_name}: no changes")

            env_changed = env_changed or module_changed

            # add module preview jobs
            if not on_default_branch or (on_default_branch and not auto_apply_main):
                preview_job_name, preview_job = \
                    ci_job(env_name, module_name, cmd='plan', module_type=module_type, cluster_name=cluster_name,
                           manual=all_jobs_are_manual or not module_changed)
                env_pipeline_jobs[preview_job_name] = preview_job

            # add module apply job
            if on_default_branch or branch_apply_enabled:
                manual = (
                    all_jobs_are_manual
                    or preview_job_name is not None
                    or helm_preview_job_name is not None
                    or not module_changed
                )

                apply_job_name, apply_job = \
                    ci_job(env_name, module_name, cmd='apply', module_type=module_type, cluster_name=cluster_name,
                           manual=manual, needs=(None if manual else prev_apply_jobs)
                           )
                env_pipeline_jobs[apply_job_name] = apply_job
                prev_apply_jobs.append(apply_job_name)

        # add env pipeline trigger job
        env_trigger_job = {
            'stage': 'Trigger',
            'needs': ['_generate-pipelines'],
            'trigger': {
                'include': [
                    {
                        'job': '_generate-pipelines',
                        'artifact': f'.gitlab/generated-{env_name}.yaml'
                    }
                ],
                "strategy": "depend"
            }
        }
        if not env_changed:
            env_trigger_job['when'] = 'manual'

        the_pipeline[f'{env_name}'] = env_trigger_job

        # add a nop job to the env_pipeline if all the jobs in it are manual
        if all([job.get('when') == 'manual' for job in env_pipeline_jobs.values()]):
            env_pipeline_jobs['nop'] = {
                'stage': 'Preview',
                'script': ['echo "This a job to keep all-jobs-manual pipelines green"', 'echo', 'printenv|sort']
            }

        # Add other staff to the pipeline, besides jobs
        env_pipeline = {
            **env_pipeline_jobs,
            **{
                'include': [
                    ".gitlab/jobs.yaml",
                ],
                'stages': ['Preview', 'Apply'],
            }
        }

        # write env pipeline to a file
        write_pipeline(f'.gitlab/generated-{env_name}.yaml', env_pipeline)

    # write the main pipeline to a file
    write_pipeline(f'.gitlab/generated.yaml', the_pipeline)


# set some global constants
CI_DEFAULT_BRANCH = os.getenv('CI_DEFAULT_BRANCH', 'main')
CI_COMMIT_REF_NAME = os.getenv('CI_COMMIT_REF_NAME',
                               subprocess.check_output(
                                   ['git', 'rev-parse', '--abbrev-ref', 'HEAD']).decode().strip())
CI_PROJECT_DIR = os.getenv('CI_PROJECT_DIR', '.')
ENVIRONMENTS_DIR = os.path.join(CI_PROJECT_DIR, 'environments')

# script entry point
if __name__ == '__main__':
    logging.basicConfig(level=logging.DEBUG, format='%(asctime)s : %(levelname)s : %(message)s')

    # fetch the latest changes of the main branch from origin.
    # we need it to compare our version to the default branch content.
    subprocess.run(['git', 'fetch', 'origin', CI_DEFAULT_BRANCH])

    # let's generate!
    main()
