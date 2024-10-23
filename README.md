# Mobile Ad-Hoc Network (MANNET) Deployment Suite

**Table of Contents**
- [Introduction](#introduction)
- [What is a MANNET?](#What-is-a-MANNET?)
- [Why Use This Tool?](#why-use-this-tool)
- [Requirements](#requirements)
- [Requisite Skills](#requisite-skills)
- [Installation](#installation)

## Introduction
B.A.T.M.A.N. advanced (often referenced as batman-adv) is an implementation of the B.A.T.M.A.N. routing protocol in the form of a Linux kernel module operating on layer 2. This repository is dedicated to making the deployment of this tool easy, quick, and versatile for almost any potential use case.

## What is a MANNET?
Mesh networking is by no means a new concept. If you're reading this in a public space (or a larger house), odds are you're connected to an access point that acts as part of a mesh. Mobile Ad Hoc Networking, however—also known as a 'MANET'—is starting to see some very interesting applications in our world. From networks of underground machinery to emergency response infrastructure and even special military operations, the term 'MANET' is becoming more well-known.

As Cisco puts it:
> "Mobile Ad Hoc Networks (MANETs) are an emerging type of wireless networking, in which mobile nodes associate on an extemporaneous or ad hoc basis. MANETs are both self-forming and self-healing, enabling peer-level communications between mobile nodes without reliance on centralized resources or fixed infrastructure.
> These attributes enable MANETs to deliver significant benefits in virtually any scenario that includes a cadre of highly mobile users or platforms, a strong need to share IP-based information, and an environment in which fixed network infrastructure is impractical, impaired, or impossible. Key applications include disaster recovery, heavy construction, mining, transportation, defense, and special event management."

## Why Use This Tool?
If you want the superpower that is mobile ad-hoc networking without spending thousdands of dollars on off the shelf solutions you're in the right place.

## Requirements
Before you can create an ad hoc mesh, you will need some hardware. This tool is designed to deploy on Debian-based Linux devices, so if it runs Debian, it will probably work (think Raspberry Pis, Libre Computer, etc.).

Second to the board itself, you will need at least **one WiFi radio**. This will most commonly be the onboard WiFi chipset of whatever board you are using, but it is still worth mentioning as a WiFi radio is a necessary component for each node. (*Note that additional WiFi dongles may be used to provide a WiFi Access Point, allowing end users to access the mesh, though this is not a requirement.)

## Requisite Skills
The idea behind this tool is to allow more typical users access to this cutting-edge technology without needing to be a Linux whiz or a networking guru. With that being said, troubleshooting is part of life with this kind of stuff, and it would behoove the installer to have some comfort with the Linux operating system (and command line), and a basic understanding of networking concepts (e.g., DHCP, DNS). Understanding the OSI model (particularly layers 2 & 3) is a bonus.

In all reality, however, you can absolutely do all of this without any of the skills mentioned above as long as you have the right attitude and the will to learn as you go.

## Installation
*This section will detail the step-by-step process to install and configure Batman-adv on your device. It includes downloading the necessary software, setting up the hardware, and configuring the network.*
