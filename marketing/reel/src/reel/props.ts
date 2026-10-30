import { z } from "zod";

export const storyProps = z.object({
  guides: z.boolean().default(false),
  bloom: z.boolean().default(true),
});

export type StoryProps = z.infer<typeof storyProps>;

export const defaultProps: StoryProps = storyProps.parse({});
