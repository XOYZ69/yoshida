<script lang="ts">
// Picks an image of the project, or adds one from the user's computer.
// Uploaded images stay in the browser (assets/images/ in the project).
import Select from "./Select.svelte";

let {
	imageFiles,
	onpick,
	upload,
	disabled = false,
}: {
	imageFiles: string[];
	onpick: (path: string) => void;
	/** Asks for an image file, adds it to the project and returns its path. */
	upload: () => Promise<string | null>;
	disabled?: boolean;
} = $props();

const UPLOAD = "\u0000upload";

async function choose(v: string) {
	if (v !== UPLOAD) return onpick(v);
	const path = await upload();
	if (path) onpick(path);
}
</script>

<Select
  value=""
  placeholder={imageFiles.length ? 'Choose or upload an image…' : 'Upload an image…'}
  label="Choose or upload an image"
  mono
  {disabled}
  options={[
    { value: UPLOAD, label: '⤒ Upload image…', detail: 'from your computer' },
    ...imageFiles.map((f) => ({ value: f, label: f.split('/').pop(), detail: f.split('/').slice(0, -1).join('/') })),
  ]}
  onchange={choose} />
