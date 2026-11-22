// "Check for updates" row for the Millennium settings panel.
//
// Queries the GitHub Releases API for the latest release when clicked (one
// request, no polling, no backend call) and compares it with the version
// baked in at build time from package.json.

import { DialogButton, Field } from '@steambrew/client';
import { version as PLUGIN_VERSION } from '../package.json';

const { useState } = (window as any).SP_REACT as { useState: <T>(v: T) => [T, (v: T) => void] };

const REPO = 'K1tsune12/kitsune-mica';

type State =
	| { kind: 'idle' }
	| { kind: 'checking' }
	| { kind: 'current'; latest: string }
	| { kind: 'available'; latest: string; url: string }
	| { kind: 'error'; message: string };

const clean = (v: string) => v.trim().replace(/^v/i, '');

/** Compares the numeric x.y.z part only; anything after it is ignored. */
export function isNewer(latest: string, current: string): boolean {
	const parse = (v: string) =>
		clean(v)
			.split(/[-+]/)[0]
			.split('.')
			.map((n) => parseInt(n, 10) || 0);
	const a = parse(latest);
	const b = parse(current);
	for (let i = 0; i < Math.max(a.length, b.length); i++) {
		const d = (a[i] ?? 0) - (b[i] ?? 0);
		if (d !== 0) return d > 0;
	}
	return false;
}

async function fetchLatest(): Promise<{ tag: string; url: string }> {
	const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
		headers: { Accept: 'application/vnd.github+json' },
	});
	if (res.status === 403 || res.status === 429) throw new Error('GitHub rate limit');
	if (!res.ok) throw new Error(`HTTP ${res.status}`);
	const json = await res.json();
	return { tag: clean(String(json.tag_name ?? '')), url: String(json.html_url ?? '') };
}

function openExternal(url: string) {
	const steam = (window as any).SteamClient;
	if (steam?.System?.OpenInSystemBrowser) steam.System.OpenInSystemBrowser(url);
	else window.open(url, '_blank');
}

export const UpdateCheckField = () => {
	const [state, setState] = useState<State>({ kind: 'idle' });

	const check = async () => {
		setState({ kind: 'checking' });
		try {
			const { tag, url } = await fetchLatest();
			if (!tag) throw new Error('no release');
			setState(isNewer(tag, PLUGIN_VERSION) ? { kind: 'available', latest: tag, url } : { kind: 'current', latest: tag });
		} catch (e) {
			setState({ kind: 'error', message: e instanceof Error ? e.message : String(e) });
		}
	};

	let description = `Installed: v${PLUGIN_VERSION}`;
	let label = 'Check for updates';
	if (state.kind === 'checking') label = 'Checking...';
	if (state.kind === 'current') description = `Up to date (v${state.latest})`;
	if (state.kind === 'error') description = `Could not check: ${state.message}`;
	if (state.kind === 'available') {
		description = `Update available: v${state.latest}`;
		label = `Open release v${state.latest}`;
	}

	return (
		<Field label="Updates" description={description}>
			<DialogButton
				style={{ minWidth: '200px' }}
				disabled={state.kind === 'checking'}
				onClick={() => {
					if (state.kind === 'available' && state.url) openExternal(state.url);
					else void check();
				}}
			>
				{label}
			</DialogButton>
		</Field>
	);
};
