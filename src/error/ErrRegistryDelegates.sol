// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

/// Thrown when a registry's approve, revoke or approved is given the zero
/// delegate, which nothing can call from and which is what an uninitialised
/// `address` reads as.
error ZeroDelegate();
