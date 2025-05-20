import {execSync} from 'node:child_process';
import {CommitParser} from 'conventional-commits-parser';

// Priority levels for determining release type
// Higher number indicates more significant change
const RELEASE_PRIORITY = {patch: 1, minor: 2, major: 3};

// Section titles for different types of changes in release notes
const SECTION_TITLES = {
    fix: 'Bug Fixes',
    feat: 'Features',
    refactor: 'Refactoring',
    docs: 'Documentation',
    perf: 'Performance',
    style: 'Styling',
    test: 'Tests',
    build: 'Build',
    ci: 'CI',
    chore: 'Misc Chores'
};

/**
 * Filters commits to include only those that affect files in the templates/ directory
 * @param {Array} commits - Array of commits to filter
 * @returns {Array} Filtered commits
 */
function filterTemplateCommits(commits) {
    return commits.filter((commit) => {
        const diffFiles = execSync(
            `git show --name-only --pretty=format: ${commit.hash}`,
            {encoding: 'utf8'}
        );
        return diffFiles.split('\n').some((file) => file.startsWith('templates/'));
    });
}

export default {
    /**
     * Analyzes commits to determine the type of release needed
     * Supports semantic versioning: major, minor, patch
     * @param {Object} pluginConfig - Plugin configuration
     * @param {Object} context - Context including commits and logger
     * @returns {string|null} Release type or null if no release needed
     */
    async analyzeCommits(pluginConfig, context) {
        const {commits, logger} = context;
        const parser = new CommitParser();

        const filteredCommits = filterTemplateCommits(commits);

        if (filteredCommits.length === 0) {
            logger.log("✅ No commits were found in the 'templates/' folder, so no release is required.");
            return null;
        }

        logger.log(`🔍 Found ${filteredCommits.length} commit(s) in 'templates/' folder.`);

        let finalReleaseType = null;
        let allCommitsAreInvalid = true;

        // Analyze each commit to determine release type
        for (const commit of filteredCommits) {
            let parsed;

            try {
                parsed = parser.parse(commit.message);
            } catch (error) {
                logger.error(`❌ Failed to parse commit message: ${commit.message}`);
                logger.error(error);
                continue;
            }

            if (!parsed?.type) {
                logger.error(`❌ Commit "${commit.hash}" is NOT Conventional Commits format!`);
                continue;
            }

            allCommitsAreInvalid = false;
            commit._parsed = parsed;

            // Check for breaking changes and determine release type
            const isBreaking = (parsed.notes || []).some((note) => note.title === 'BREAKING CHANGE');
            let commitRelease = null;

            if (isBreaking) {
                commitRelease = 'major';
            } else if (parsed.revert) {
                commitRelease = 'patch';
            } else {
                switch (parsed.type) {
                    case 'feat':
                        commitRelease = 'minor';
                        break;
                    case 'fix':
                    case 'perf':
                    case 'build':
                    case 'refactor':
                    case 'chore':
                    case 'ci':
                    case 'style':
                        commitRelease = 'patch';
                        break;
                    case 'docs':
                    case 'test':
                        commitRelease = null;
                        break;
                    default:
                        commitRelease = null;
                }
            }

            // Skip release if scope is 'no-release'
            if (parsed.scope === 'no-release') {
                commitRelease = null;
            }

            // Update final release type based on priority
            if (commitRelease && (!finalReleaseType || RELEASE_PRIORITY[commitRelease] > RELEASE_PRIORITY[finalReleaseType])) {
                finalReleaseType = commitRelease;
            }
        }

        if (allCommitsAreInvalid) {
            logger.error(
                "❌ Found changes in 'templates/' folder, but no valid Conventional Commits.\n" +
                "Please fix commit messages and try again."
            );
            throw new Error("No valid Conventional Commits in templates changes.");
        }

        logger.log(`✅ Computed release type: ${finalReleaseType || 'none'}`);
        return finalReleaseType;
    },

    /**
     * Generates formatted release notes from commits
     * Groups changes by type (features, fixes, etc.)
     * @param {Object} pluginConfig - Plugin configuration
     * @param {Object} context - Context including nextRelease, commits, and logger
     * @returns {string} Formatted release notes in markdown format
     */
    async generateNotes(pluginConfig, context) {
        const {logger, nextRelease, commits} = context;
        const parser = new CommitParser();

        const filteredCommits = filterTemplateCommits(commits);
        logger.log('📝 Generating release notes...');

        // Parse commits and track unique subjects starting from latest
        const uniqueSubjects = new Map();
        const parsedCommits = filteredCommits.reverse().map(commit => {
            try {
                const parsed = parser.parse(commit.message);
                const key = parsed?.subject || commit.message;
                if (!uniqueSubjects.has(key)) {
                    uniqueSubjects.set(key, commit.hash);
                    return {...commit, _parsed: parsed};
                }
                return null;
            } catch (error) {
                logger.error(`Failed to parse commit: ${commit.message}`);
                return null;
            }
        }).filter(Boolean);

        const version = nextRelease.version;
        const releaseDate = new Date().toISOString().split('T')[0];
        let notes = `## ${version} (${releaseDate})\n\n`;

        // Initialize categories for commit types
        const categorizedCommits = Object.keys(SECTION_TITLES).reduce((acc, type) => {
            acc[type] = [];
            return acc;
        }, {});

        // Group commits by their type
        for (const commit of parsedCommits) {
            const parsed = commit._parsed;
            if (!parsed?.type) continue;

            const shortHash = commit.hash.slice(0, 7);
            const line = `- ${parsed.subject} (${shortHash})`;

            if (SECTION_TITLES[parsed.type]) {
                categorizedCommits[parsed.type].push(line);
            } else {
                categorizedCommits.chore.push(line);
            }
        }

        // Generate formatted notes sections
        for (const [type, title] of Object.entries(SECTION_TITLES)) {
            const commitsList = categorizedCommits[type];
            if (!commitsList?.length) continue;

            notes += `### ${title}\n\n${commitsList.join('\n')}\n\n`;
        }

        return notes.trim();
    }
};