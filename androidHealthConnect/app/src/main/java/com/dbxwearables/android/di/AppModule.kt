package com.dbxwearables.android.di

import android.content.Context
import com.dbxwearables.android.data.remote.APIConfiguration
import com.dbxwearables.android.data.remote.APIService
import com.dbxwearables.android.data.repository.SyncLedger
import com.dbxwearables.android.data.repository.SyncStateRepository
import com.dbxwearables.android.domain.sync.SyncCoordinator
import com.dbxwearables.android.health.HealthConnectManager
import com.dbxwearables.android.health.HealthConnectQueryService
import com.dbxwearables.android.util.DeviceIdentifier
import com.dbxwearables.android.util.SecureStorage
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    @Provides
    @Singleton
    fun provideOkHttpClient(): OkHttpClient {
        return OkHttpClient.Builder()
            .connectTimeout(APIConfiguration.TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(APIConfiguration.TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .writeTimeout(APIConfiguration.TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .build()
    }
}
