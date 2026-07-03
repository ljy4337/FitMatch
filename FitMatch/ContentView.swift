//
//  ContentView.swift
//  FitMatch
//
//  Created by 이진영 on 7/3/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                MyClosetView()
            }
            .tabItem {
                Label("My Closet", systemImage: "tshirt")
            }

            NavigationStack {
                ShoppingProductFormView()
            }
            .tabItem {
                Label("추천", systemImage: "sparkles")
            }
        }
    }
}
