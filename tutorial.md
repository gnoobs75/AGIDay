# Tutorial Mode - Implementation & Maintenance Guide

## Original Implementation Prompt

Use this prompt (or adapt it) when adding Tutorial Mode to a new project:

```
Add a "Tutorial Mode" setting that shows contextual help guides for users.

**Core Requirements:**
- Toggle button in the UI header (persists across sessions via localStorage)
- Shows a guide panel relevant to the current screen/stage
- Default: ON for new users, can be disabled anytime
- Users can dismiss tutorials per-screen (remembers dismissals)
- Reset option to restore all dismissed tutorials

**Guide Content Structure (for each screen):**
- Introduction: 1-2 sentence overview of what this screen does
- Quick Start: Numbered checklist (5-7 steps) for getting started fast
- Step-by-Step Sections: Expandable detailed guides for each feature area
- Terminology Glossary: Definitions for all technical terms used
- Tips: Pro tips and best practices
- Warnings: Important notes and limitations
- Troubleshooting: Common issues with solutions

**UI Design:**
- Collapsible panel at top of content area
- Tabs for: "Step-by-Step" | "Glossary" | "Tips & Issues"
- Visual hierarchy: icons, numbered steps, color-coded sections
- Dismiss button per-screen
- Compact toggle button (icon only) in header

**Content Coverage:**
[List all screens/stages in your app]
- Screen 1: [description]
- Screen 2: [description]
- etc.

**Terminology to Define:**
[List technical terms users need to understand]
- Term 1
- Term 2
- etc.
```

---

## File Structure

```
frontend/src/
├── content/
│   └── tutorials.ts          # All tutorial content
├── components/
│   └── tutorial/
│       ├── index.ts          # Exports
│       ├── TutorialPanel.tsx # Main display component
│       └── TutorialToggle.tsx# Toggle button component
└── stores/
    └── settingsStore.ts      # Tutorial mode state
```

---

## How to Add a New Screen's Tutorial

### Step 1: Define the Tutorial Object

In `frontend/src/content/tutorials.ts`, add a new tutorial:

```typescript
export const newScreenTutorial: StageTutorial = {
  id: 'new-screen',           // Unique ID
  stageName: 'New Screen',    // Display name
  title: 'Screen Title',      // Header title
  introduction: 'Brief description of what this screen does.',

  sections: [
    {
      title: 'Section Name',
      content: 'What this section covers.',
      steps: [
        {
          title: 'Step 1',
          description: 'What to do.',
          tip: 'Optional helpful tip.',
        },
        // More steps...
      ],
      terminology: [
        {
          term: 'Technical Term',
          definition: 'What it means.',
          example: 'Optional example.',
        },
        // More terms...
      ],
      tips: ['Pro tip 1', 'Pro tip 2'],
      warnings: ['Important note'],
    },
    // More sections...
  ],

  quickStart: [
    'Step 1 of quick start',
    'Step 2 of quick start',
    // 5-7 steps total
  ],

  commonIssues: [
    {
      problem: 'Something doesn\'t work',
      solution: 'How to fix it',
    },
    // More issues...
  ],
};
```

### Step 2: Register the Tutorial

Add to the `allTutorials` object in `tutorials.ts`:

```typescript
export const allTutorials: Record<string, StageTutorial> = {
  // ... existing tutorials
  'new-screen': newScreenTutorial,
};
```

### Step 3: Connect to Your Screen

In the component that renders your screen, add:

```typescript
import { TutorialPanel } from '../tutorial';
import { getTutorialForStage } from '../../content/tutorials';
import { useSettingsStore } from '../../stores/settingsStore';

function YourScreen() {
  const { tutorialMode } = useSettingsStore();
  const tutorial = getTutorialForStage('new-screen');

  return (
    <div>
      {tutorialMode && tutorial && (
        <TutorialPanel tutorial={tutorial} stageId="new-screen" />
      )}
      {/* Rest of your screen */}
    </div>
  );
}
```

---

## How to Update Existing Tutorials

### Adding a New Feature to a Screen

1. Open `frontend/src/content/tutorials.ts`
2. Find the relevant tutorial (e.g., `uploadStageTutorial`)
3. Add to the appropriate section:

```typescript
// Adding a new step
sections: [
  {
    title: 'Existing Section',
    steps: [
      // ... existing steps
      {
        title: 'New Feature',
        description: 'How to use the new feature.',
        tip: 'Helpful tip about it.',
      },
    ],
  },
],
```

### Adding New Terminology

```typescript
terminology: [
  // ... existing terms
  {
    term: 'New Term',
    definition: 'Clear explanation.',
    example: 'Concrete example if helpful.',
  },
],
```

### Adding a New Tip

```typescript
tips: [
  // ... existing tips
  'New helpful tip about the feature.',
],
```

### Adding a Troubleshooting Item

```typescript
commonIssues: [
  // ... existing issues
  {
    problem: 'Description of what goes wrong',
    solution: 'How to fix it',
  },
],
```

---

## Content Writing Guidelines

### Introduction
- 1-2 sentences max
- Answer: "What does this screen do?"
- No jargon

### Quick Start
- 5-7 numbered steps
- Action-oriented verbs: "Click", "Select", "Enter", "Wait"
- Can complete the main task following just these steps

### Step-by-Step Sections
- Group related features together
- Each step has: title, description, optional tip
- Tips for non-obvious behavior only

### Terminology
- Define terms when first used in your app
- Include example if the term is abstract
- Sort alphabetically in glossary view

### Tips
- Things users might not discover on their own
- Performance optimizations
- Keyboard shortcuts
- Best practices

### Warnings
- Limitations users should know
- Things that might cause confusion
- Irreversible actions

### Troubleshooting
- Real issues users encounter
- Clear problem description
- Actionable solution

---

## Maintenance Checklist

Run through this when you make UI changes:

### When Adding a New Feature
- [ ] Add steps explaining how to use it
- [ ] Add any new terminology
- [ ] Add tips for non-obvious behavior
- [ ] Update Quick Start if it changes the main flow
- [ ] Add troubleshooting for known issues

### When Changing Existing UI
- [ ] Update step descriptions to match new UI
- [ ] Update screenshots/references if any
- [ ] Remove steps for removed features
- [ ] Update terminology if names changed

### When Fixing Bugs
- [ ] Remove troubleshooting items for fixed bugs
- [ ] Add troubleshooting for any new known issues

### Quarterly Review
- [ ] Read through all tutorials for accuracy
- [ ] Remove outdated information
- [ ] Add commonly asked questions from users
- [ ] Check all terminology is still accurate

---

## Testing Tutorial Changes

1. **Enable Tutorial Mode** - Click book icon in header
2. **Navigate to updated screen** - Verify panel appears
3. **Check all tabs**:
   - Step-by-Step: All sections expand/collapse
   - Glossary: Terms sorted alphabetically
   - Tips & Issues: Content displays correctly
4. **Test Quick Start** - Steps are numbered and clear
5. **Test Dismiss** - Hiding works per-screen
6. **Test Persistence** - Refresh page, settings retained

---

## Okyaku-Specific Screens

Current tutorials implemented for:

| Screen ID | Screen Name | Key Content |
|-----------|-------------|-------------|

---

## Terminology Master List

Keep this updated as you add terms:

### Generation Terms
- Source Image, Background Removal, Inference, VRAM
- Mesh, Vertices, Polygons, Decimation, Normal

### Text-to-Image Terms
- Prompt, Negative Prompt, Style Preset, Seed
- Guidance Scale, Inference Steps

### Texture Terms
- Texture Map, Albedo/Diffuse, UV Mapping
- Texture Resolution, Texel, Baking, Seams

### Rigging Terms
- Skeleton/Armature, Bone, Joint, Root Bone
- Weight Painting, Skinning, Bind Pose
- Humanoid, Quadruped, Bone Hierarchy
- Vertex Weights, Max Influences

### Animation Terms
- Keyframe, Frame Rate, Duration, Interpolation
- Animation Preset, Procedural Animation
- Speed, Intensity, Blend Factor, Loop Mode
- Mixamo, FBX, Retargeting, Bone Mapping, Bone Coverage

### Export Terms
- GLB, glTF, FBX, OBJ
- Engine Preset, Coordinate System
- Embedded Textures, Embedded Animations, LODs

---

## Future Enhancements

Ideas for improving Tutorial Mode:

- [ ] Video tutorials embedded in panels
- [ ] Interactive walkthroughs (highlight UI elements)
- [ ] Progress tracking (mark tutorials as "completed")
- [ ] Search across all tutorials
- [ ] Contextual tooltips on hover
- [ ] "Learn more" links to documentation
- [ ] User feedback ("Was this helpful?")
- [ ] Localization support
