---
title: 'JawAtlas: a free, offline mobile companion for learning dental cone beam CT anatomy'
tags:
  - dental education
  - radiology
  - cone beam computed tomography
  - DICOM
  - augmented reality
  - iOS
authors:
  - name: Silvester Cekodhima
    affiliation: 1
affiliations:
  - name: Independent developer
    index: 1
date: 16 September 2026
bibliography: paper.bib
---

# Summary

JawAtlas is a free, open-source iOS and iPadOS application that turns a dental cone beam computed tomography (CBCT) scan into an interactive study companion. Learners can rotate a ray-marched 3D rendering of the jaw, read tri-planar multiplanar reconstructions (MPR) with correct radiological orientation labels, trace the dental arch to build a panoramic reconstruction with a linked cross-section, take millimetre and angle measurements, and place the scan life-size on a table in augmented reality (AR) to slice through it by moving the device. Educators can mark structures, caption them as "moments", replay them like slides, and share whole cases with a class. The app works completely offline, has no accounts or analytics, and ships with an openly licensed demo scan [@feng2025dataset], so a student can start learning within seconds of installing it.

# Statement of need

CBCT is now routine in dentistry [@scarfe2008cbct], yet most students first meet it as flat slides in a lecture. Reading a CBCT volume is a spatial skill: learners must connect the axial, coronal and sagittal planes, understand where each slice cuts through the anatomy, and learn conventions such as viewing axial images from the feet. Clinical CBCT suites teach none of this explicitly. They are licensed per workstation, tied to the lab, and designed for clinicians who already know the conventions. General research tools such as 3D Slicer [@fedorov2012slicer] are powerful but desktop-bound and have a steep learning curve for a first-year dental student.

JawAtlas targets that gap. It is designed for dental students, dental educators and researchers who want a small, correct and approachable tool on the device students already carry. The design choices follow from teaching needs:

- **Explicit, labelled modes.** Move, Adjust, Measure and Angle are separate modes with step-by-step guidance, and a first-open explainer teaches the crosshair, scout-line colours and tools in plain language.
- **Conventions taught, not hidden.** Orientation labels (R, L, A, P, H, F) are derived from the DICOM orientation cosines, so they remain correct on oblique cuts. The panoramic view follows the orthopantomogram convention.
- **Honest intensities.** Values are labelled as grey values rather than Hounsfield units, because CBCT intensities are not calibrated densities, and learners should meet that fact early.
- **Privacy by construction.** The importer reads only a whitelist of technical DICOM tags, automated tests check that no identifying string reaches storage, and an audit script rejects any networking code. This lets educators use the app in classrooms without data-protection review of a cloud service.

JawAtlas is explicitly an education and training aid. It is not a medical device and is not intended for diagnosis or treatment planning.

# Learning objectives and use in teaching

After working through the bundled case, a learner should be able to:

1. Relate the axial, coronal and sagittal planes to one another using a shared crosshair and scout lines.
2. Identify patient orientation on any slice using the radiological convention.
3. Explain how a panoramic image is reconstructed from a curved path through the dental arch, and relate a point on the panoramic view to its cross-section.
4. Take linear and angular measurements and explain why CBCT grey values are not Hounsfield units.
5. Describe the three-dimensional course of structures such as the mandibular canal by slicing through the volume in AR.

Educators can author teaching cases without programming: slice to a structure, mark it, write a caption, save it as a moment, and share the case file over AirDrop or the Files app. Students can batch-import a folder of shared cases and export a PDF summary of marked views for revision.

<!-- TODO(author): before submission, describe how JawAtlas has been used or piloted in teaching (course, cohort size, feedback), as JOSE asks for the story of the project and its use in a learning context. -->

# Implementation

JawAtlas is written in Swift 6 with SwiftUI and Metal and has no third-party dependencies. The `JawAtlasCore` Swift package contains a from-scratch DICOM parser supporting implicit and explicit VR little endian, deflated, RLE lossless and JPEG lossless (processes 14 and 70) transfer syntaxes, a series builder, geometry and a memory-mapped voxel store. The volume is uploaded once to a 3D Metal texture; the 3D view is a full-screen ray marcher [@levoy1988display] with central-difference gradients, while the MPR panes and panoramic reconstruction are single-pass fragment shaders sampling the same texture. The AR mode reuses the same plane mathematics with the camera pose as the plane source. About 160 XCTest cases cover the parser (including a 240-case mutation corpus), codecs, a hardened ZIP reader, volume geometry checked against 3D Slicer ground truth, orientation labels, arch-curve mathematics, measurements and the case store. Continuous integration runs the audit gates and the test suite on every change.

# Acknowledgements

The bundled demo case is from the openly licensed dataset by Feng, Li, Gu, Wang and Yu [@feng2025dataset], used under CC BY 4.0.

# References
