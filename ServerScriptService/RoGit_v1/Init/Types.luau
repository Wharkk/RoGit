export type GitHubConfig = {
	owner: string,
	repo: string,
	token: string,
	branch: string,
}

export type ApiResult<T = nil> = {
	ok: boolean,
	data: T?,
	error: string?,
}

export type TreeEntry = {
	path: string,
	mode: string,
	type: string,
	sha: string?,
	size: number?,
	content: string?,
}

export type CommitInfo = {
	sha: string,
	shortSha: string,
	message: string,
	author: string,
	date: string,
}

export type BranchInfo = {
	name: string,
	sha: string,
	protected: boolean,
}

export type SerializedInstance = {
	className: string,
	properties: { [string]: any },
	attributes: { [string]: any },
	tags: { string }?,
	name: string?, -- stored when filename differs from instance name (disambiguation)
}

export type ScriptMeta = {
	attributes: { [string]: any }?,
	tags: { string }?,
	enabled: boolean?,
	runContext: string?,
	name: string?, -- stored when filename differs from instance name
}

export type FileChange = {
	path: string,
	status: "added" | "modified" | "deleted",
	localContent: string?,
	remoteSha: string?,
}

return nil